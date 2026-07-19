extends "res://scripts/fragments/chunks/data_fragment_chunk.gd"

const LevelDecoratorScript := preload("res://scripts/generation/level_decorator.gd")

## Campaign hosts can use this hand-off to play the rejection beat before the pursuit clock
## starts. Fragment preview keeps the immediate starting-gun behavior by default.
signal tags_rejected

## THE LOCKOUT CHASE (GDD §12.1; corridor spec docs/LOCKOUT_CHASE.md; canon mechanics
## reference-docs/chase_scene_framework.md): the Act 1 climax. The party's tags fail at the
## simulation-boundary checkpoint; Naturalizer waves pursue them back down the corridor to Endo's
## maintained wall. Levers (framework canon: recognizable on first sight, never regenerating):
## the sealable service door, the Chelator cluster's protocol hesitation, a Flure decoy, a
## Scarpet run — and the UNMARKED offshoot pocket behind a portal pair, whose Hushbloom
## double-seal is the decline-path expert solution (knowledge-gated; no UI flag, no hint).
## Tyreg's junction choice: ACCEPT arms her Suppress escort; ignoring her prices the decline
## wave. Endo's wall is a REAL shelter region (the sanctuary law) — the chase ends where the
## institution stops. Waves and levers all ride the scheduler; failure = party wipe -> the
## loader's restart (the reset system's chassis).

const PLAZA_X := 6.0
const TRENCH_X0 := 15.0          # the uncrossable service trench at the stretch's throat
const TRENCH_X1 := 19.5
const WASH_X := 120.0            # S4: the wash undercut (the channels quote -- a REAL Channel)
const BARRICADE_X0 := 158.0      # S5: the collapse shelf's debris wall (clamber over)
const BARRICADE_X1 := 161.5
# PINCH POINTS (director's crowd governor): narrow gaps the party threads smoothly; a pursuer
# barreling in TRIPS (prone = an obstacle), and the pack behind CLAMBERS OVER the body at a
# per-body delay -- the crowd's speed self-regulates at every pinch, scaling with pack size.
const PINCHES := [[58.0, 1.5], [112.0, -1.5], [152.5, 0.0]]   # [x, gap centre z]; #3 = the rubble apron guarding the clamber queue
const PINCH_GAP_HALF := 1.1
const TRIP_SECS := 2.6
const CLIMB_SECS := 1.6
const TRIP_REFRACTORY := 5.0
const DOOR_X := 42.0
const CHELATOR_X := 55.0
const JUNCTION_X := 76.0
const OFFSHOOT_Z := 14.0
const OFFSHOOT_EXIT_X := 90.0
const WALL_X := 205.0
const CORRIDOR_HALF_Z := 5.0

const DOOR_HOLD_SECS := 7.0      # how long the sealed door holds a wave (they cut through)
const SEAL_SECS := 22.0          # the Hushbloom portal seal (covers one full search cycle)
const NAT_SPEED := 4.4           # party base 3.0. EFFECTIVE pursuit is ~half the raw speed (the
                                 # rescan tail-chase), so 6.0 closes on a runner at ~0.4 wu/s —
                                 # sprint-only fails late-corridor; the door hold (7 s) + chelator
                                 # break buy the escape margin (probe-tuned, framework knob)
const CLOSE_CALL_RANGE := 4.5    # the breathing-down-your-neck warning distance
# THE PAIR LAW (director): solo play carries you a long way, but not to the end -- the shelf
# clamber is a boost-and-pull two-person move, and Endo's wall rest counts heads. And RUNBACKS
# ARE CHECKPOINTS: the corridor remembers the furthest section boundary the PAIR cleared
# together; a wipe resumes there with the world kept (the gantry stays down, spent levers stay
# spent -- levers never regenerate) and only the pack resets.
const CHECKPOINTS := [50.0, 92.0, 128.0, 163.0]
# Broken-pair fail lines. Most are the runback markers themselves; the extra line on the
# barricade apron is deliberately BEFORE the two-person clamber, so a lone survivor cannot
# become stranded at the shelf, and the final line catches a broken pair before Endo's rest.
const PAIR_FAIL_BOUNDARIES := [50.0, 92.0, 128.0, BARRICADE_X0 - 4.0, 163.0, WALL_X - 16.0]
const PAIR_NEAR_X := 12.0        # how far behind the shelf a boosting partner may stand
const SUPPRESS_CHARGES := 3
const SUPPRESS_SECS := 5.0

# Four paired rally sectors turn the long retreat into sustained, player-authored chase play.
# Entry and commit are both real 4.8-second actions. Between them, the live clock only advances
# while the pair is together and either moving or under nearby Naturalizer pressure; hiding in a
# quiet corner therefore cannot manufacture the duration. Six specialist stations, one spatial
# strategy choice, and two selected branch executions fit inside every live window.
const LOCKOUT_RALLY_WORK_SECONDS := 4.8
const LOCKOUT_RALLY_LIVE_SECONDS := 80.9
const LOCKOUT_RALLY_STAGE_FLOOR_SECONDS := 90.5
const LOCKOUT_RALLY_PAIR_RADIUS := 13.5
const LOCKOUT_RALLY_ACTIVE_THREAT_RADIUS := 18.0
const LOCKOUT_RALLY_RUN_SPEED := 5.0
const LOCKOUT_RALLY_TICK_SECONDS := 0.5
const LOCKOUT_RALLY_TICK_TAG := "lockout_rally_tick"

# The pre-extension baseline comes from the current human playthrough measurement. It remains
# separately named so this contract never misrepresents inherited time as newly instrumented work.
const LOCKOUT_EXISTING_ACTIVE_SECONDS := 113.5
const LOCKOUT_EXISTING_TOTAL_SECONDS := 316.5
const LOCKOUT_EXISTING_MAX_SINGLE_MODE_SECONDS := 44.0
const LOCKOUT_EXISTING_MAX_DEAD_GAP_SECONDS := 4.5
# Each live-sector directive is non-blocking and plays over the first two seconds of player work.
# That replaces eight seconds of presentation previously measured in series with the course.
const LOCKOUT_OVERLAPPED_PRESENTATION_SECONDS := 8.0

const LOCKOUT_RALLY_STAGES := [
	{
		"id": "records",
		"display": "RECORDS RELAY",
		"center": Vector3(48.0, 0.0, 0.0),
		"common": [
			{"id": "index_trace", "role": "aster", "verb": "TRACE", "display": "trace the rejected index", "offset": Vector3(-3.6, 0.0, -2.6)},
			{"id": "checksum_read", "role": "aster", "verb": "READ", "display": "read the checksum drift", "offset": Vector3(-0.9, 0.0, -3.0)},
			{"id": "shutter_route", "role": "aster", "verb": "ROUTE", "display": "route the archive shutter", "offset": Vector3(2.2, 0.0, -2.5)},
			{"id": "rail_brace", "role": "peris", "verb": "BRACE", "display": "brace the buckled rail", "offset": Vector3(-3.1, 0.0, 2.7)},
			{"id": "counterweight_free", "role": "peris", "verb": "FREE", "display": "free the counterweight", "offset": Vector3(0.0, 0.0, 3.0)},
			{"id": "cable_tension", "role": "peris", "verb": "TENSION", "display": "tension the shutter cable", "offset": Vector3(3.3, 0.0, 2.5)},
		],
		"strategies": [
			{
				"id": "north_shutter", "display": "DROP NORTH SHUTTER", "role": "aster",
				"offset": Vector3(3.9, 0.0, -1.2), "effect": "shutter", "relief": 7.0,
				"executions": [
					{"id": "decode_shutter", "role": "aster", "verb": "DECODE", "display": "decode the north latch", "offset": Vector3(1.4, 0.0, -3.8)},
					{"id": "drop_shutter", "role": "peris", "verb": "DROP", "display": "drop the north shutter", "offset": Vector3(-2.0, 0.0, -3.7)},
				],
			},
			{
				"id": "south_echo", "display": "LOOP SOUTH SIGNAL", "role": "aster",
				"offset": Vector3(3.9, 0.0, 1.2), "effect": "decoy", "relief": 4.5,
				"executions": [
					{"id": "splice_echo", "role": "aster", "verb": "SPLICE", "display": "splice the credential echo", "offset": Vector3(1.4, 0.0, 3.8)},
					{"id": "cast_echo", "role": "peris", "verb": "CAST", "display": "cast the false return", "offset": Vector3(-2.0, 0.0, 3.7)},
				],
			},
		],
	},
	{
		"id": "relay",
		"display": "JUNCTION RELAY",
		"center": Vector3(96.0, 0.0, 0.0),
		"common": [
			{"id": "relay_map", "role": "aster", "verb": "MAP", "display": "map the relay aliases", "offset": Vector3(-3.7, 0.0, -2.5)},
			{"id": "portal_phase", "role": "aster", "verb": "PHASE", "display": "read the portal phase", "offset": Vector3(-0.8, 0.0, -3.0)},
			{"id": "protocol_cut", "role": "aster", "verb": "CUT", "display": "cut the pursuit protocol", "offset": Vector3(2.3, 0.0, -2.5)},
			{"id": "relay_ground", "role": "peris", "verb": "GROUND", "display": "ground the relay frame", "offset": Vector3(-3.2, 0.0, 2.7)},
			{"id": "chelator_prime", "role": "peris", "verb": "PRIME", "display": "prime the chelator salts", "offset": Vector3(0.0, 0.0, 3.0)},
			{"id": "return_valve", "role": "peris", "verb": "VENT", "display": "vent the return valve", "offset": Vector3(3.3, 0.0, 2.5)},
		],
		"strategies": [
			{
				"id": "north_portal", "display": "FEINT THROUGH NORTH", "role": "aster",
				"offset": Vector3(3.9, 0.0, -1.2), "effect": "decoy", "relief": 5.0,
				"executions": [
					{"id": "seed_portal", "role": "aster", "verb": "SEED", "display": "seed the portal afterimage", "offset": Vector3(1.5, 0.0, -3.8)},
					{"id": "swing_frame", "role": "peris", "verb": "SWING", "display": "swing the return frame", "offset": Vector3(-2.1, 0.0, -3.7)},
				],
			},
			{
				"id": "south_chelator", "display": "DRAG THROUGH CHELATOR", "role": "aster",
				"offset": Vector3(3.9, 0.0, 1.2), "effect": "chelator", "relief": 8.0,
				"executions": [
					{"id": "mark_hesitation", "role": "aster", "verb": "MARK", "display": "mark the hesitation lane", "offset": Vector3(1.5, 0.0, 3.8)},
					{"id": "spill_chelator", "role": "peris", "verb": "SPILL", "display": "spill the chelator charge", "offset": Vector3(-2.1, 0.0, 3.7)},
				],
			},
		],
	},
	{
		"id": "wash",
		"display": "WASH RECOVERY",
		"center": Vector3(132.0, 0.0, 0.0),
		"common": [
			{"id": "sweep_read", "role": "aster", "verb": "READ", "display": "read the sweep cadence", "offset": Vector3(-3.7, 0.0, -2.5)},
			{"id": "drain_route", "role": "aster", "verb": "ROUTE", "display": "route the undercut drain", "offset": Vector3(-0.8, 0.0, -3.0)},
			{"id": "gate_sync", "role": "aster", "verb": "SYNC", "display": "sync the wash gate", "offset": Vector3(2.3, 0.0, -2.5)},
			{"id": "grate_lift", "role": "peris", "verb": "LIFT", "display": "lift the fouled grate", "offset": Vector3(-3.2, 0.0, 2.7)},
			{"id": "pressure_bleed", "role": "peris", "verb": "BLEED", "display": "bleed the pressure drum", "offset": Vector3(0.0, 0.0, 3.0)},
			{"id": "handrail_lock", "role": "peris", "verb": "LOCK", "display": "lock the recovery rail", "offset": Vector3(3.3, 0.0, 2.5)},
		],
		"strategies": [
			{
				"id": "north_wash", "display": "RIDE THE NORTH SWEEP", "role": "aster",
				"offset": Vector3(3.9, 0.0, -1.2), "effect": "wash", "relief": 3.5,
				"executions": [
					{"id": "open_sluice", "role": "aster", "verb": "OPEN", "display": "open the north sluice", "offset": Vector3(1.5, 0.0, -3.8)},
					{"id": "brace_sweep", "role": "peris", "verb": "BRACE", "display": "brace through the sweep", "offset": Vector3(-2.1, 0.0, -3.7)},
				],
			},
			{
				"id": "south_bypass", "display": "OPEN SOUTH BYPASS", "role": "aster",
				"offset": Vector3(3.9, 0.0, 1.2), "effect": "shutter", "relief": 6.5,
				"executions": [
					{"id": "release_bypass", "role": "aster", "verb": "RELEASE", "display": "release the bypass latch", "offset": Vector3(1.5, 0.0, 3.8)},
					{"id": "haul_bypass", "role": "peris", "verb": "HAUL", "display": "haul the bypass leaf", "offset": Vector3(-2.1, 0.0, 3.7)},
				],
			},
		],
	},
	{
		"id": "collapse",
		"display": "COLLAPSE RUNBACK",
		"center": Vector3(176.0, 0.0, 0.0),
		"common": [
			{"id": "load_trace", "role": "aster", "verb": "TRACE", "display": "trace the shelf load", "offset": Vector3(-3.7, 0.0, -2.5)},
			{"id": "pinch_map", "role": "aster", "verb": "MAP", "display": "map the broken pinch", "offset": Vector3(-0.8, 0.0, -3.0)},
			{"id": "wall_signal", "role": "aster", "verb": "SIGNAL", "display": "signal Endo's wall", "offset": Vector3(2.3, 0.0, -2.5)},
			{"id": "rubble_wedge", "role": "peris", "verb": "WEDGE", "display": "wedge the rubble shelf", "offset": Vector3(-3.2, 0.0, 2.7)},
			{"id": "haul_line", "role": "peris", "verb": "HAUL", "display": "haul the boost line", "offset": Vector3(0.0, 0.0, 3.0)},
			{"id": "landing_brace", "role": "peris", "verb": "BRACE", "display": "brace the far landing", "offset": Vector3(3.3, 0.0, 2.5)},
		],
		"strategies": [
			{
				"id": "north_pinch", "display": "PILE THE NORTH PINCH", "role": "aster",
				"offset": Vector3(3.9, 0.0, -1.2), "effect": "trip", "relief": 7.0,
				"executions": [
					{"id": "cant_rubble", "role": "aster", "verb": "CANT", "display": "cant the rubble face", "offset": Vector3(1.5, 0.0, -3.8)},
					{"id": "pull_tripline", "role": "peris", "verb": "PULL", "display": "pull the tripline", "offset": Vector3(-2.1, 0.0, -3.7)},
				],
			},
			{
				"id": "south_suppress", "display": "BUILD SOUTH FIRELINE", "role": "aster",
				"offset": Vector3(3.9, 0.0, 1.2), "effect": "suppress", "relief": 6.0,
				"executions": [
					{"id": "range_marker", "role": "aster", "verb": "MARK", "display": "mark the suppression range", "offset": Vector3(1.5, 0.0, 3.8)},
					{"id": "raise_screen", "role": "peris", "verb": "RAISE", "display": "raise the firing screen", "offset": Vector3(-2.1, 0.0, 3.7)},
				],
			},
		],
	},
]

var _chase_started := false
var _door_sealed := false
var _tyreg_accepted := false
var _decline_wave_fired := false
var _bloom_carry := 0            # picked hushblooms in hand (the carried throw, v1 abstraction)
var _pad_in: PortalPad
var _pad_out: PortalPad
var _wave_count := 0
var _door_held := {}             # char_id -> true: the door holds each cutter exactly once
var _last_close_call := -100.0
var _checkpoint_x := -1.0
var _defer_pursuit_start := false
var _pursuit_armed := false
var _rally_nodes := {}
var _rally_completed_actions := {}
var _rally_choices := {}
var _rally_completed_stages := {}
var _rally_elapsed_by_stage := {}
var _rally_history: Array = []
var _rally_stage_index := 0
var _rally_phase := "awaiting_entry"
var _rally_elapsed := 0.0
var _decoration_audit := {}

func set_pursuit_start_deferred(deferred: bool) -> void:
	_defer_pursuit_start = deferred

func begin_deferred_pursuit() -> void:
	_arm_chase_pursuit()

func get_scene_title() -> String:
	return "The Lockout Chase"

func _build_chunk() -> void:
	fragment = _chase_fragment()
	super._build_chunk()
	_build_checkpoint()
	_build_trench()
	_build_terminal_rows()
	_build_door()
	_build_barricade()
	_build_pinches()
	_build_chelator()
	_build_offshoot()
	_build_tyreg_junction()
	_build_endo_wall()
	_build_rally_stages()
	_decoration_audit = LevelDecoratorScript.decorate_profile(self, "lockout", {
		"x0": 0.0,
		"x1": 220.0,
		"width": CORRIDOR_HALF_Z * 2.0,
		"wall_height": 3.2,
		"ground_y": 0.0,
		"spacing": 8.4,
		"seed": 0x10C0A7,
		"signs": ["CIVIC LIMIT", "PAIR RELAY", "MAINTAINED SECTION  >"],
	})
	for hb in _hushblooms:
		if is_instance_valid(hb):
			hb.picked.connect(func() -> void: _bloom_carry += 1)

## --- The corridor fragment (floors, grid, spawns, loader-kind objects) ---

func _chase_fragment() -> Fragment:
	var frag := Fragment.new()
	frag.id = "lockout_chase"
	frag.title = "The Lockout Chase"
	frag.help = "Tags rejected. Run the corridor you came down — the levers you learned, now under pursuit."
	frag.default_character = "aster"
	frag.party_ids = PackedStringArray(["aster", "peris"])
	frag.spawns = {"aster": Vector3(PLAZA_X, 0.5, 1.0), "peris": Vector3(PLAZA_X, 0.5, -1.0)}
	frag.floors = [
		{"pos": Vector3(111.0, -0.05, 0.0), "size": Vector3(222.0, 0.1, CORRIDOR_HALF_Z * 2.0),
			"color": Color(0.10, 0.10, 0.12), "tile": "deck_metal"},
		# the offshoot pocket floor (portal-only access: its island is walled off the corridor)
		{"pos": Vector3(JUNCTION_X + 4.0, -0.05, OFFSHOOT_Z), "size": Vector3(8.0, 0.1, 5.0),
			"color": Color(0.08, 0.08, 0.10), "tile": "deck_metal"},
	]
	frag.walls = [
		{"pos": Vector3(111.0, 1.6, CORRIDOR_HALF_Z + 0.2), "size": Vector3(222.0, 3.2, 0.4),
			"color": Color(0.07, 0.07, 0.09)},
		{"pos": Vector3(111.0, 1.6, -CORRIDOR_HALF_Z - 0.2), "size": Vector3(222.0, 3.2, 0.4),
			"color": Color(0.07, 0.07, 0.09)},
		# the offshoot pocket's own shell
		{"pos": Vector3(JUNCTION_X + 4.0, 1.4, OFFSHOOT_Z + 2.7), "size": Vector3(8.4, 2.8, 0.3),
			"color": Color(0.06, 0.06, 0.08)},
		{"pos": Vector3(JUNCTION_X + 4.0, 1.4, OFFSHOOT_Z - 2.7), "size": Vector3(8.4, 2.8, 0.3),
			"color": Color(0.06, 0.06, 0.08)},
		{"pos": Vector3(JUNCTION_X - 0.4, 1.4, OFFSHOOT_Z), "size": Vector3(0.3, 2.8, 5.6),
			"color": Color(0.06, 0.06, 0.08)},
		{"pos": Vector3(JUNCTION_X + 8.4, 1.4, OFFSHOOT_Z), "size": Vector3(0.3, 2.8, 5.6),
			"color": Color(0.06, 0.06, 0.08)},
	]
	frag.lights = [
		{"pos": Vector3(10.0, 4.0, 0.0), "color": Color(0.72, 0.84, 1.0), "energy": 2.6, "range": 18.0},
		{"pos": Vector3(32.0, 3.5, 0.0), "color": Color(0.36, 0.91, 0.5), "energy": 1.1, "range": 20.0},
		{"pos": Vector3(70.0, 3.5, 0.0), "color": Color(0.8, 0.78, 0.72), "energy": 1.4, "range": 26.0},
		{"pos": Vector3(WASH_X, 3.5, 0.0), "color": Color(0.5, 0.7, 0.75), "energy": 1.3, "range": 22.0},
		{"pos": Vector3(170.0, 3.5, 0.0), "color": Color(0.6, 0.55, 0.5), "energy": 1.2, "range": 24.0},
		{"pos": Vector3(WALL_X, 3.5, 0.0), "color": Color(0.95, 0.8, 0.55), "energy": 2.0, "range": 16.0},
	]
	frag.labels = [{"pos": Vector3(PLAZA_X, 3.4, 0.0), "text": "SIMULATION BOUNDARY — SECTION 3B",
		"color": Color(0.72, 0.84, 1.0)}]
	frag.objects = [
		# levers the party already knows, placed where the spec puts them
		{"type": "flure", "name": "DecoyFlure", "pos": Vector3(60.0, 0.5, 3.4), "radius": 1.5,
			"targets": [], "attract": 20.0},
		{"type": "scarpet", "name": "ScarpetRun", "pos": Vector3(105.0, 0.0, -2.0), "radius": 2.2},
		{"type": "channel", "name": "LockoutWash", "x": 120.0, "half": 2.2, "z_half": 5.0,
			"period": 7.0, "dur": 2.2, "phase": 2.0, "tag": "lockout_wash"},
		# the two pickable stun blooms the expert path needs (S2 + S3)
		{"type": "hushbloom", "name": "BloomA", "pos": Vector3(50.0, 0.0, -3.6),
			"opts": {"trigger_radius": 0.0, "regen_secs": 0.0}},
		{"type": "hushbloom", "name": "BloomB", "pos": Vector3(72.0, 0.0, 3.8),
			"opts": {"trigger_radius": 0.0, "regen_secs": 0.0}},
		{"type": "exit_shelter", "name": "EndoWall", "pos": Vector3(WALL_X + 4.0, 0.5, 0.0),
			"radius": 1.6, "label": "ENDO'S WALL", "color": Color(0.95, 0.8, 0.55)},
	]
	frag.params = {"restart_on_wipe": true}
	frag.time_state = {"note_default": "The checkpoint refused the tags. The way home is the way out.",
		"routing_mode": "direct"}
	var cs := 1.5
	var w := 148
	var hgrid := 14
	var cells: Array = []
	for z in range(hgrid):
		for x in range(w):
			var wx := (float(x) + 0.5) * cs
			var wz := (float(z) + 0.5) * cs - 10.5
			var in_corridor: bool = absf(wz) < CORRIDOR_HALF_Z - 0.2 and wx < 220.0
			var in_pocket: bool = wz > OFFSHOOT_Z - 2.4 and wz < OFFSHOOT_Z + 2.4 \
				and wx > JUNCTION_X - 0.2 and wx < JUNCTION_X + 8.2
			# S1 record hall: two staggered TERMINAL ROWS (the stacks quote) -- solid banks the
			# whole chase weaves around (the flow field routes pursuit around them live)
			var in_bank_a: bool = wx > 24.0 and wx < 28.5 and wz < 0.6
			var in_bank_b: bool = wx > 33.0 and wx < 37.5 and wz > -0.6
			# S5 collapse shelf: the debris barricade -- no walking through; the clamber is the way
			var in_barricade: bool = wx > BARRICADE_X0 and wx < BARRICADE_X1
			# pinch walls: everything but the narrow gap is blocked at each pinch line
			var in_pinch_wall := false
			for pin in PINCHES:
				if wx > float((pin as Array)[0]) - 0.9 and wx < float((pin as Array)[0]) + 0.9 \
						and absf(wz - float((pin as Array)[1])) > 1.1:
					in_pinch_wall = true
			if (in_corridor or in_pocket) and not (in_corridor and (in_bank_a or in_bank_b or in_barricade or in_pinch_wall)):
				cells.append([x, z])
	frag.grid = {"contract_id": "unified_grid_v1", "cell_size": cs,
		"origin": [0.0, 0.0, -10.5], "width": w, "height": hgrid, "walkable_cells": cells}
	return frag

## --- The checkpoint (S0): the facility kind + the trigger ---

func _build_checkpoint() -> void:
	_spawn_landmark_building({"kind": "facility_checkpoint", "pos": Vector3(PLAZA_X - 8.0, 0, 0),
		"yaw": -PI * 0.5, "spec_seed": 0})
	var scanner := _add_interactable(self, "BoundaryScanner", "Present tags at the boundary scanner",
		Vector3(PLAZA_X - 3.0, 0, 0), "PRESENT TAGS", "", 0.8, true, 1.6,
		Interactable.InteractableType.INSPECTION, false)
	var body := _add_box(scanner, Vector3(0, 0.8, 0), Vector3(0.3, 0.8, 0.3), Color(0.7, 0.72, 0.75),
		Color(0.36, 0.91, 0.5), 1.4)
	_outline_interactable_child(scanner, body, "BoundaryScanner", 1.6)
	scanner.interacted.connect(_on_tags_rejected)

## The trigger: rejection escalates, the waves take the corridor (the timetable, not a leash).
func _on_tags_rejected() -> void:
	if _chase_started:
		return
	_chase_started = true
	_drop_gantry()
	_set_preview_step("lockout_rejected")
	_show_note("TAG INCOHERENT // ACCESS DENIED. Concealed positions open behind you.", 3.0)
	tags_rejected.emit()
	if _defer_pursuit_start:
		return
	_arm_chase_pursuit()

## --- Paired rally sectors: live survival, spatial decisions, and persistent execution ---

func _build_rally_stages() -> void:
	for stage_index in range(LOCKOUT_RALLY_STAGES.size()):
		var stage: Dictionary = LOCKOUT_RALLY_STAGES[stage_index]
		var stage_id := str(stage.get("id", "stage_%d" % stage_index))
		var center: Vector3 = stage.get("center", Vector3.ZERO)
		var root_node := Node3D.new()
		root_node.name = "LockoutRallyFrame_%s" % stage_id
		add_child(root_node)
		_build_rally_frame(root_node, stage_index, stage)

		var nodes := {"common": {}, "choices": {}, "branches": {}}
		var entry := _add_rally_interactable(
			root_node, stage_id, "entry", "ASTER", center + Vector3(-4.2, 0.0, 0.0),
			"LATCH", "aster", Color(0.42, 0.72, 0.95), "latch the pair into %s" % str(stage.get("display", stage_id)))
		entry.set_meta("rally_kind", "entry")
		entry.interacted.connect(_on_rally_entered.bind(stage_index, entry))
		nodes["entry"] = entry

		for action_variant in (stage.get("common", []) as Array):
			var action: Dictionary = action_variant
			var action_id := str(action.get("id", "work"))
			var role := str(action.get("role", ""))
			var action_node := _add_rally_interactable(
				root_node, stage_id, action_id, role.to_upper(), center + (action.get("offset", Vector3.ZERO) as Vector3),
				str(action.get("verb", "WORK")), role, _rally_role_color(role), str(action.get("display", action_id)))
			action_node.set_meta("rally_kind", "specialist_work")
			action_node.interacted.connect(_on_rally_common_completed.bind(stage_index, action_id, action_node))
			(nodes["common"] as Dictionary)[action_id] = action_node

		for strategy_variant in (stage.get("strategies", []) as Array):
			var strategy: Dictionary = strategy_variant
			var strategy_id := str(strategy.get("id", "strategy"))
			var strategy_role := str(strategy.get("role", "aster"))
			var strategy_color := _rally_strategy_color(strategy_id)
			var choice := _add_rally_interactable(
				root_node, stage_id, "choose_%s" % strategy_id, strategy_role.to_upper(),
				center + (strategy.get("offset", Vector3.ZERO) as Vector3), "CHOOSE", strategy_role,
				strategy_color, str(strategy.get("display", strategy_id)))
			choice.set_meta("rally_kind", "strategy_choice")
			choice.set_meta("rally_strategy", strategy_id)
			choice.interacted.connect(_on_rally_strategy_chosen.bind(stage_index, strategy_id, choice))
			(nodes["choices"] as Dictionary)[strategy_id] = choice

			var execution_nodes := {}
			var execution_index := 0
			for execution_variant in (strategy.get("executions", []) as Array):
				var execution: Dictionary = execution_variant
				var execution_id := str(execution.get("id", "execute_%d" % execution_index))
				var execution_role := str(execution.get("role", ""))
				var execution_node := _add_rally_interactable(
					root_node, stage_id, execution_id, execution_role.to_upper(),
					center + (execution.get("offset", Vector3.ZERO) as Vector3),
					str(execution.get("verb", "EXECUTE")), execution_role, strategy_color,
					str(execution.get("display", execution_id)))
				execution_node.set_meta("rally_kind", "branch_execution")
				execution_node.set_meta("rally_strategy", strategy_id)
				execution_node.interacted.connect(_on_rally_branch_executed.bind(
					stage_index, strategy_id, execution_id, execution_index, execution_node))
				execution_nodes[execution_id] = execution_node
				execution_index += 1
			(nodes["branches"] as Dictionary)[strategy_id] = execution_nodes

		var commit := _add_rally_interactable(
			root_node, stage_id, "commit", "PERIS", center + Vector3(4.2, 0.0, 0.0),
			"COMMIT", "peris", Color(0.36, 0.91, 0.50), "commit the pair's cleared route")
		commit.set_meta("rally_kind", "commit")
		commit.interacted.connect(_on_rally_committed.bind(stage_index, commit))
		nodes["commit"] = commit
		_rally_nodes[stage_id] = nodes
	_reset_rally_progress()

func _build_rally_frame(parent: Node3D, stage_index: int, stage: Dictionary) -> void:
	var center: Vector3 = stage.get("center", Vector3.ZERO)
	var stage_id := str(stage.get("id", "stage_%d" % stage_index))
	var tint := Color(0.42, 0.72, 0.95).lerp(Color(0.95, 0.64, 0.32), float(stage_index) / 3.0)
	# Measured structural bay: wall-hugging uprights, an overhead datum, a numbered beacon, and
	# two floor routes. Everything is visual-only and leaves the full chase/navigation lane clear.
	for side in [-1.0, 1.0]:
		_add_box(parent, center + Vector3(0.0, 1.55, float(side) * 4.55),
			Vector3(0.24, 3.10, 0.32), Color(0.24, 0.27, 0.31), tint, 0.35,
			"LockoutRallyUpright_%s_%s" % [stage_id, "N" if side < 0.0 else "S"])
		_add_box(parent, center + Vector3(-2.4, 2.65, float(side) * 4.42),
			Vector3(4.6, 0.14, 0.12), Color(0.18, 0.21, 0.25), tint, 0.85)
	_add_box(parent, center + Vector3(0.0, 3.05, 0.0), Vector3(0.30, 0.22, 9.15),
		Color(0.28, 0.31, 0.35), tint, 0.75, "LockoutRallyCrossbeam_%s" % stage_id)
	for route_z in [-3.35, 3.35]:
		_add_box(parent, center + Vector3(0.0, 0.026, float(route_z)), Vector3(8.8, 0.022, 0.07),
			Color(0.04, 0.05, 0.06), tint, 1.1, "LockoutRallyDatum_%s" % stage_id)
	_add_box(parent, center + Vector3(0.0, 2.42, -4.36), Vector3(1.2, 0.46, 0.08),
		Color(0.06, 0.08, 0.11), tint, 1.6, "LockoutRallyBeacon_%s" % stage_id)
	_add_label(parent, "%02d // %s" % [stage_index + 1, str(stage.get("display", stage_id))],
		center + Vector3(0.0, 2.42, -4.24), tint.lightened(0.18))
	var light := _add_light(parent, center + Vector3(0.0, 2.8, 0.0), tint, 0.82, 9.5)
	light.name = "LockoutRallyLight_%s" % stage_id

func _add_rally_interactable(parent: Node3D, stage_id: String, action_id: String, role_label: String,
		position: Vector3, verb: String, role: String, tint: Color, description: String) -> Area3D:
	var node_name := "LockoutRally_%s_%s" % [stage_id, action_id]
	var interactable := _add_interactable(parent, node_name, description, position, verb, role,
		LOCKOUT_RALLY_WORK_SECONDS, true, 1.45, Interactable.InteractableType.TIMED_ACTION, false)
	interactable.set_meta("rally_stage", stage_id)
	interactable.set_meta("rally_action", action_id)
	var pedestal := _add_box(interactable, Vector3(0.0, 0.38, 0.0), Vector3(0.54, 0.76, 0.54),
		Color(0.14, 0.16, 0.19), tint, 0.55, "%sBody" % node_name)
	_add_box(interactable, Vector3(0.0, 0.82, 0.0), Vector3(0.72, 0.12, 0.72),
		Color(0.26, 0.29, 0.33), tint, 1.25, "%sReadout" % node_name)
	var role_plate := _add_label(interactable, role_label, Vector3(0.0, 1.18, 0.0), tint.lightened(0.20))
	role_plate.font_size = 30
	role_plate.pixel_size = 0.007
	_outline_interactable_child(interactable, pedestal, node_name, 1.45)
	interactable.set_interaction_enabled(false)
	return interactable

func _rally_role_color(role: String) -> Color:
	return Color(0.42, 0.72, 0.95) if role == "aster" else Color(0.36, 0.91, 0.50)

func _rally_strategy_color(strategy_id: String) -> Color:
	return Color(0.48, 0.78, 1.0) if "north" in strategy_id else Color(0.95, 0.62, 0.28)

func _all_rally_interactables() -> Array:
	var result: Array = []
	for stage_nodes_variant in _rally_nodes.values():
		var stage_nodes: Dictionary = stage_nodes_variant
		result.append(stage_nodes.get("entry"))
		result.append(stage_nodes.get("commit"))
		for node in (stage_nodes.get("common", {}) as Dictionary).values():
			result.append(node)
		for node in (stage_nodes.get("choices", {}) as Dictionary).values():
			result.append(node)
		for branch_variant in (stage_nodes.get("branches", {}) as Dictionary).values():
			for node in (branch_variant as Dictionary).values():
				result.append(node)
	return result

func _reset_rally_progress() -> void:
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag(LOCKOUT_RALLY_TICK_TAG)
	_rally_completed_actions.clear()
	_rally_choices.clear()
	_rally_completed_stages.clear()
	_rally_elapsed_by_stage.clear()
	_rally_history.clear()
	_rally_stage_index = 0
	_rally_phase = "awaiting_entry"
	_rally_elapsed = 0.0
	for interactable in _all_rally_interactables():
		if interactable == null or not is_instance_valid(interactable):
			continue
		if interactable.has_method("reset"):
			interactable.call("reset")
		interactable.set_interaction_enabled(false)
	if not LOCKOUT_RALLY_STAGES.is_empty():
		var first_id := str((LOCKOUT_RALLY_STAGES[0] as Dictionary).get("id", ""))
		var first_entry = (_rally_nodes.get(first_id, {}) as Dictionary).get("entry")
		if first_entry != null:
			first_entry.set_interaction_enabled(true)

func _cancel_rally_dwells() -> void:
	for interactable in _all_rally_interactables():
		if interactable != null and is_instance_valid(interactable) \
				and interactable.has_method("cancel_pending_interaction"):
			interactable.call("cancel_pending_interaction")

func _rally_action_key(stage_id: String, action_id: String) -> String:
	return "%s:%s" % [stage_id, action_id]

func _rally_pair_state(stage_index: int) -> String:
	var gs = _get_game_state()
	if gs == null:
		return "missing_state"
	var stage: Dictionary = LOCKOUT_RALLY_STAGES[stage_index]
	var center: Vector3 = stage.get("center", Vector3.ZERO)
	for cid in ["aster", "peris"]:
		if not _pair_member_present(gs, cid) or gs.is_downed(cid):
			return "broken"
	for cid in ["aster", "peris"]:
		var pos: Vector3 = gs.get_position(cid)
		if Vector2(pos.x - center.x, pos.z - center.z).length() > LOCKOUT_RALLY_PAIR_RADIUS:
			return "separated"
	return "ready"

func _refuse_rally_action(interactable: Node, message: String, keep_enabled := true) -> void:
	_show_note(message, 2.4)
	if interactable != null and interactable.has_method("reset"):
		interactable.call("reset")
		if not keep_enabled:
			interactable.set_interaction_enabled(false)

func _break_pair_at_rally() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	_cancel_rally_dwells()
	var survivor := ""
	for cid in ["aster", "peris"]:
		if _pair_member_present(gs, cid) and not gs.is_downed(cid):
			survivor = cid
			break
	if survivor != "":
		gs.down_character(survivor)
		if fragment != null and not gs.is_party_downed(Array(fragment.party_ids)):
			_schedule_broken_pair_reset(gs, survivor)
	_show_note("The relay loses one signal. The chase resets the broken pair.", 2.6)

func _rally_pair_gate(stage_index: int, interactable: Node) -> bool:
	if not _chase_started:
		_refuse_rally_action(interactable, "The relay is quiet until the checkpoint rejects you.")
		return false
	var pair_state := _rally_pair_state(stage_index)
	if pair_state == "ready":
		return true
	if pair_state == "broken":
		_refuse_rally_action(interactable, "One signal is gone.")
		_break_pair_at_rally()
	else:
		_refuse_rally_action(interactable, "Bring Aster and Peris into the marked bay together.")
	return false

func _on_rally_entered(stage_index: int, interactable: Node) -> void:
	if stage_index != _rally_stage_index or _rally_phase != "awaiting_entry":
		_refuse_rally_action(interactable, "This relay is not the live one.", false)
		return
	if not _rally_pair_gate(stage_index, interactable):
		return
	var stage: Dictionary = LOCKOUT_RALLY_STAGES[stage_index]
	var stage_id := str(stage.get("id", ""))
	_rally_phase = "surviving"
	_rally_elapsed = float(_rally_elapsed_by_stage.get(stage_id, 0.0))
	for node in ((_rally_nodes[stage_id] as Dictionary).get("common", {}) as Dictionary).values():
		node.set_interaction_enabled(true)
	_ensure_rally_pressure(stage_index)
	_arm_rally_tick()
	_set_preview_step("lockout_rally_%s" % stage_id)
	_show_note("PAIR LATCHED // Work the bay while the pursuit is live.", 2.5)

func _on_rally_common_completed(stage_index: int, action_id: String, interactable: Node) -> void:
	if stage_index != _rally_stage_index or _rally_phase != "surviving":
		_refuse_rally_action(interactable, "That relay is no longer live.", false)
		return
	if not _rally_pair_gate(stage_index, interactable):
		return
	var stage: Dictionary = LOCKOUT_RALLY_STAGES[stage_index]
	var stage_id := str(stage.get("id", ""))
	_rally_completed_actions[_rally_action_key(stage_id, action_id)] = true
	_apply_rally_work_pulse(stage_index)
	if _rally_common_complete(stage):
		for node in ((_rally_nodes[stage_id] as Dictionary).get("choices", {}) as Dictionary).values():
			node.set_interaction_enabled(true)
		_show_note("Six reads agree. Choose a physical lane and execute it.", 2.2)

func _on_rally_strategy_chosen(stage_index: int, strategy_id: String, interactable: Node) -> void:
	if stage_index != _rally_stage_index or _rally_phase != "surviving":
		_refuse_rally_action(interactable, "That decision window has closed.", false)
		return
	if not _rally_pair_gate(stage_index, interactable):
		return
	var stage: Dictionary = LOCKOUT_RALLY_STAGES[stage_index]
	var stage_id := str(stage.get("id", ""))
	if not _rally_common_complete(stage):
		_refuse_rally_action(interactable, "Finish both specialists' reads before choosing.")
		return
	_rally_choices[stage_id] = strategy_id
	_rally_completed_actions[_rally_action_key(stage_id, "choose_%s" % strategy_id)] = true
	var stage_nodes: Dictionary = _rally_nodes[stage_id]
	for choice_id in (stage_nodes.get("choices", {}) as Dictionary):
		var choice_node = (stage_nodes.get("choices", {}) as Dictionary)[choice_id]
		choice_node.set_interaction_enabled(false)
	for execution_node in (((stage_nodes.get("branches", {}) as Dictionary).get(strategy_id, {})) as Dictionary).values():
		execution_node.set_interaction_enabled(true)
	var strategy := _rally_strategy_by_id(stage, strategy_id)
	_show_note("ROUTE HELD // %s. Execute both ends." % str(strategy.get("display", strategy_id)), 2.5)

func _on_rally_branch_executed(stage_index: int, strategy_id: String, action_id: String,
		execution_index: int, interactable: Node) -> void:
	if stage_index != _rally_stage_index or _rally_phase != "surviving":
		_refuse_rally_action(interactable, "That branch is no longer live.", false)
		return
	if not _rally_pair_gate(stage_index, interactable):
		return
	var stage: Dictionary = LOCKOUT_RALLY_STAGES[stage_index]
	var stage_id := str(stage.get("id", ""))
	if str(_rally_choices.get(stage_id, "")) != strategy_id:
		_refuse_rally_action(interactable, "The pair committed to the other lane.", false)
		return
	_rally_completed_actions[_rally_action_key(stage_id, action_id)] = true
	_apply_rally_strategy_effect(stage_index, strategy_id, execution_index)
	_refresh_rally_commit(stage_index)

func _on_rally_committed(stage_index: int, interactable: Node) -> void:
	if stage_index != _rally_stage_index or _rally_phase != "surviving":
		_refuse_rally_action(interactable, "That relay is already settled.", false)
		return
	if not _rally_pair_gate(stage_index, interactable):
		return
	var stage: Dictionary = LOCKOUT_RALLY_STAGES[stage_index]
	var stage_id := str(stage.get("id", ""))
	if not _rally_branch_complete(stage) or _rally_elapsed + 0.001 < LOCKOUT_RALLY_LIVE_SECONDS:
		_refuse_rally_action(interactable, "The lane is not stable yet. Keep moving under pressure.")
		return
	_rally_completed_stages[stage_id] = true
	_rally_elapsed_by_stage[stage_id] = _rally_elapsed
	_rally_history.append({
		"stage": stage_id,
		"strategy": str(_rally_choices.get(stage_id, "")),
		"live_seconds": _rally_elapsed,
	})
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag(LOCKOUT_RALLY_TICK_TAG)
	var gs = _get_game_state()
	if gs != null:
		_advance_checkpoint(gs)
	_apply_rally_clear_relief(stage_index)
	_rally_stage_index += 1
	_rally_elapsed = 0.0
	if _rally_stage_index < LOCKOUT_RALLY_STAGES.size():
		_rally_phase = "awaiting_entry"
		var next_id := str((LOCKOUT_RALLY_STAGES[_rally_stage_index] as Dictionary).get("id", ""))
		var next_entry = (_rally_nodes.get(next_id, {}) as Dictionary).get("entry")
		if next_entry != null:
			next_entry.set_interaction_enabled(true)
		_show_note("PAIR CHECKPOINT HELD // Take the next live relay.", 2.4)
	else:
		_rally_phase = "complete"
		_set_preview_step("lockout_rallies_complete")
		_show_note("ALL PAIR RELAYS HELD // Endo's wall can receive both of you.", 3.0)

func _rally_common_complete(stage: Dictionary) -> bool:
	var stage_id := str(stage.get("id", ""))
	for action_variant in (stage.get("common", []) as Array):
		var action: Dictionary = action_variant
		if not bool(_rally_completed_actions.get(_rally_action_key(stage_id, str(action.get("id", ""))), false)):
			return false
	return true

func _rally_branch_complete(stage: Dictionary) -> bool:
	var stage_id := str(stage.get("id", ""))
	var strategy_id := str(_rally_choices.get(stage_id, ""))
	if strategy_id == "":
		return false
	var strategy := _rally_strategy_by_id(stage, strategy_id)
	for execution_variant in (strategy.get("executions", []) as Array):
		var execution: Dictionary = execution_variant
		if not bool(_rally_completed_actions.get(
				_rally_action_key(stage_id, str(execution.get("id", ""))), false)):
			return false
	return true

func _rally_strategy_by_id(stage: Dictionary, strategy_id: String) -> Dictionary:
	for strategy_variant in (stage.get("strategies", []) as Array):
		var strategy: Dictionary = strategy_variant
		if str(strategy.get("id", "")) == strategy_id:
			return strategy
	return {}

func _refresh_rally_commit(stage_index: int) -> void:
	if stage_index != _rally_stage_index or _rally_phase != "surviving":
		return
	var stage: Dictionary = LOCKOUT_RALLY_STAGES[stage_index]
	if not _rally_branch_complete(stage) or _rally_elapsed + 0.001 < LOCKOUT_RALLY_LIVE_SECONDS:
		return
	var stage_id := str(stage.get("id", ""))
	var commit = (_rally_nodes.get(stage_id, {}) as Dictionary).get("commit")
	if commit != null:
		commit.set_interaction_enabled(true)

func _arm_rally_tick() -> void:
	var sched = _get_scheduler()
	if sched == null or _rally_phase != "surviving" \
			or _rally_elapsed + 0.001 >= LOCKOUT_RALLY_LIVE_SECONDS:
		return
	var step_seconds := minf(LOCKOUT_RALLY_TICK_SECONDS, LOCKOUT_RALLY_LIVE_SECONDS - _rally_elapsed)
	sched.cancel_tag(LOCKOUT_RALLY_TICK_TAG)
	sched.schedule_after(step_seconds, _rally_tick.bind(step_seconds), LOCKOUT_RALLY_TICK_TAG)

func _rally_tick(step_seconds := LOCKOUT_RALLY_TICK_SECONDS) -> void:
	if _rally_phase != "surviving" or _rally_stage_index >= LOCKOUT_RALLY_STAGES.size():
		return
	var pair_state := _rally_pair_state(_rally_stage_index)
	if pair_state == "broken":
		_break_pair_at_rally()
		return
	var stage: Dictionary = LOCKOUT_RALLY_STAGES[_rally_stage_index]
	var stage_id := str(stage.get("id", ""))
	if pair_state == "ready" and _rally_tick_is_meaningful(_rally_stage_index):
		_rally_elapsed = minf(LOCKOUT_RALLY_LIVE_SECONDS, _rally_elapsed + float(step_seconds))
		_rally_elapsed_by_stage[stage_id] = _rally_elapsed
		_refresh_rally_commit(_rally_stage_index)
	_arm_rally_tick()

func _rally_tick_is_meaningful(stage_index: int) -> bool:
	var gs = _get_game_state()
	if gs == null:
		return false
	for cid in ["aster", "peris"]:
		if gs.characters.has(cid) and gs.is_moving(cid):
			return true
	if _rally_has_active_work(stage_index):
		return true
	var center: Vector3 = (LOCKOUT_RALLY_STAGES[stage_index] as Dictionary).get("center", Vector3.ZERO)
	for enemy in _enemies:
		if not is_instance_valid(enemy) or not enemy.is_alive() or enemy.is_stunned():
			continue
		var pos: Vector3 = gs.get_position(enemy.char_id)
		if Vector2(pos.x - center.x, pos.z - center.z).length() <= LOCKOUT_RALLY_ACTIVE_THREAT_RADIUS:
			return true
	return false

func _rally_has_active_work(stage_index: int) -> bool:
	var stage_id := str((LOCKOUT_RALLY_STAGES[stage_index] as Dictionary).get("id", ""))
	var stage_nodes: Dictionary = _rally_nodes.get(stage_id, {})
	var candidates: Array = []
	candidates.append_array((stage_nodes.get("common", {}) as Dictionary).values())
	candidates.append_array((stage_nodes.get("choices", {}) as Dictionary).values())
	for branch_variant in (stage_nodes.get("branches", {}) as Dictionary).values():
		candidates.append_array((branch_variant as Dictionary).values())
	candidates.append(stage_nodes.get("commit"))
	for node in candidates:
		if node != null and is_instance_valid(node) and node.has_method("_is_dwelling") \
				and bool(node.call("_is_dwelling")):
			return true
	return false

func _ensure_rally_pressure(stage_index: int) -> void:
	for enemy in _enemies:
		if is_instance_valid(enemy) and enemy.is_alive():
			return
	# Ordinarily the original concealed waves are already on the pair. This only closes the edge
	# case where a rally is entered before a delayed wave or after every pursuer has been removed.
	_spawn_wave(1, true)
	_arm_pursuit_director()
	var stage_id := str((LOCKOUT_RALLY_STAGES[stage_index] as Dictionary).get("id", ""))
	_show_note("%s draws a fresh niche response." % stage_id.capitalize(), 1.8)

func _rally_nearby_enemies(stage_index: int, radius: float) -> Array:
	var result: Array = []
	var gs = _get_game_state()
	if gs == null:
		return result
	var center: Vector3 = (LOCKOUT_RALLY_STAGES[stage_index] as Dictionary).get("center", Vector3.ZERO)
	for enemy in _enemies:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		var pos: Vector3 = gs.get_position(enemy.char_id)
		var distance := Vector2(pos.x - center.x, pos.z - center.z).length()
		if distance <= radius:
			result.append({"enemy": enemy, "distance": distance, "position": pos})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("distance", INF)) < float(b.get("distance", INF)))
	return result

func _apply_rally_work_pulse(stage_index: int) -> void:
	var nearby := _rally_nearby_enemies(stage_index, 11.0)
	if not nearby.is_empty():
		var enemy = (nearby[0] as Dictionary).get("enemy")
		if enemy != null and not enemy.is_stunned():
			enemy.stun(1.6)

func _apply_rally_strategy_effect(stage_index: int, strategy_id: String, execution_index: int) -> void:
	var stage: Dictionary = LOCKOUT_RALLY_STAGES[stage_index]
	var strategy := _rally_strategy_by_id(stage, strategy_id)
	var effect := str(strategy.get("effect", "suppress"))
	var relief := float(strategy.get("relief", 5.0)) + float(execution_index) * 0.8
	var nearby := _rally_nearby_enemies(stage_index, 22.0)
	var gs = _get_game_state()
	var center: Vector3 = stage.get("center", Vector3.ZERO)
	var lane_z := -3.6 if "north" in strategy_id else 3.6
	var affected := 0
	for enemy_data_variant in nearby:
		var enemy_data: Dictionary = enemy_data_variant
		var enemy = enemy_data.get("enemy")
		if enemy == null:
			continue
		if effect == "suppress" and affected >= 2:
			break
		if effect == "wash" and gs != null:
			var pos: Vector3 = enemy_data.get("position", center)
			gs.snap_character_to(enemy.char_id, Vector3(maxf(TRENCH_X1 + 1.0, pos.x - 4.0), 0.0, pos.z))
		elif effect == "decoy" and gs != null:
			gs.command_move_to_pos(enemy.char_id, Vector3(center.x - 6.0, 0.0, lane_z))
		elif effect == "trip":
			_fallen[enemy.char_id] = true
		enemy.stun(relief)
		affected += 1
	_show_note("%s executes: %d pursuer%s displaced." % [
		str(strategy.get("display", strategy_id)), affected, "" if affected == 1 else "s"], 1.8)

func _apply_rally_clear_relief(stage_index: int) -> void:
	for enemy_data_variant in _rally_nearby_enemies(stage_index, 18.0):
		var enemy = (enemy_data_variant as Dictionary).get("enemy")
		if enemy != null:
			enemy.stun(3.0)

func _arm_chase_pursuit() -> void:
	if not _chase_started or _pursuit_armed:
		return
	_pursuit_armed = true
	var sched = _get_scheduler()
	if sched == null:
		return
	# the shake beat covers the activation delay — the party gets a REAL head start (canon:
	# initial distance ~18 wu, seen and heard; spawning on their heels made the trailing member
	# die in the record hall every run)
	sched.schedule_after(4.5, _spawn_wave.bind(2, false), "chase_wave_1")
	# wave 2 activates from CONCEALED WALL NICHES at the party's own segment (canon: "Naturalizers
	# activate from concealed positions" — not all from the plaza; the corridor itself is hostile)
	sched.schedule_after(14.0, _spawn_wave.bind(2, true), "chase_wave_2")
	sched.schedule_after(1.0, _decline_watch, "chase_decline_watch")
	sched.schedule_after(1.5, _close_call_watch, "chase_close_call")
	sched.schedule_after(1.0, _hazard_poll, "chase_hazards")
	_wire_wash_sweep()
	_arm_portal_follow()
	sched.schedule_after(2.2, func() -> void:
		_show_note("RUN. East — Endo keeps the wall past the old corridors.", 2.8), "chase_directive")

func _spawn_wave(count: int, near_party := false, base_x_override := -1.0) -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	var base_x := 2.0
	if base_x_override > 0.0:
		base_x = base_x_override
	elif near_party and gs.characters.has("aster"):
		base_x = clampf(gs.get_position("aster").x - 9.0, 2.0, WALL_X - 20.0)
	for i in range(count):
		var eid := "naturalizer_%d" % _wave_count
		_wave_count += 1
		var nz := (-3.8 if i % 2 == 0 else 3.8) if near_party else (-2.0 + 2.0 * float(i))
		# detect 0: chase waves are driven by the pursuit DIRECTOR (engage_target), not the stealth
		# detection layer — leaving detection on made the predictive scheduler re-fire in-range
		# events on every command (the measured 90+ ms/tick storm)
		_spawn_enemy({"id": eid, "class": "naturalizer", "pos": Vector3(base_x, 0.5, nz),
			"speed": NAT_SPEED, "detect": 0.0, "coop_exempt": true,
			"targets": ["aster", "peris"]}, gs)
		_wire_wave_nat(eid)
	_show_note("Naturalizers out of the wall niches — behind you.", 1.8)
	_arm_pursuit_director()

## THE CHASE CONTRACT (framework): pursuit is RELENTLESS — pursuers track the fleeing party down
## the whole corridor, no detection-radius leash. The director re-engages any pursuer that has
## dropped back to a scanning state toward the nearest party member engage_target() will accept:
## downed, sheltered, and FULLY CONCEALED targets are refused there, so Endo's wall and the
## offshoot tight-hides still break the track (the expert path's whole premise).
func _arm_pursuit_director() -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	sched.cancel_tag("chase_pursuit")
	sched.schedule_after(0.8, _pursuit_director, "chase_pursuit")

## THE PACK'S SHARED PURSUIT FIELD (crowd memoization): ONE breadth-first distance field from the
## quarry's cell per director tick, over the walkable grid — every pursuer's hop just descends
## the field. Replaces N near-identical per-unit path queries per rescan (the residual spike
## source: an unreachable quarry made each unit's A* sweep the region before failing; the BFS
## pays that cost once, bounded, for everyone). Derived state on the scheduler cadence —
## deterministic, replay-safe.
var _flow_field := {}          # Vector2i -> int (steps to the quarry)
const _FLOW_DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

func _refresh_flow_field() -> void:
	_flow_field.clear()
	var gs = _get_game_state()
	if gs == null or gs.grid == null:
		return
	# seed from every ENGAGEABLE quarry (mirrors the engage gates: downed/sheltered/hidden break the field)
	var frontier: Array = []
	for cid in ["aster", "peris"]:
		if not gs.characters.has(cid):
			continue
		if gs.is_downed(cid) or gs.is_at_shelter(cid) or gs.is_character_hidden(cid):
			continue
		var c: Vector2i = gs.grid.world_to_grid(gs.get_position(cid))
		_flow_field[c] = 0
		frontier.append(c)
	var head := 0
	while head < frontier.size():
		var cur: Vector2i = frontier[head]
		head += 1
		var d: int = int(_flow_field[cur]) + 1
		for dir in _FLOW_DIRS:
			var nxt: Vector2i = cur + dir
			if _flow_field.has(nxt):
				continue
			if not gs.grid.is_walkable(nxt.x, nxt.y):
				continue
			_flow_field[nxt] = d
			frontier.append(nxt)

## The hop a pursuer takes: descend the shared field one cell (fall back to a capped straight hop
## when the field has no answer — quarry hidden, off-grid, or the pocket island).
func _flow_hop(from_pos: Vector3, fallback_target: Vector3) -> Vector3:
	var gs = _get_game_state()
	if gs == null or gs.grid == null or _flow_field.is_empty():
		return from_pos + (fallback_target - from_pos).limit_length(5.0)
	var c: Vector2i = gs.grid.world_to_grid(from_pos)
	var best := c
	var best_d: int = int(_flow_field.get(c, 1 << 30))
	for dir in _FLOW_DIRS:
		var nxt: Vector2i = c + dir
		var nd: int = int(_flow_field.get(nxt, 1 << 30))
		if nd < best_d:
			best_d = nd
			best = nxt
	if best == c:
		return from_pos + (fallback_target - from_pos).limit_length(5.0)
	# step two cells down the field per hop so the rescan cadence never starves the stride
	var second := best
	var second_d: int = best_d
	for dir2 in _FLOW_DIRS:
		var nxt2: Vector2i = best + dir2
		var nd2: int = int(_flow_field.get(nxt2, 1 << 30))
		if nd2 < second_d:
			second_d = nd2
			second = nxt2
	return gs.grid.grid_to_world(second)

func _pursuit_director() -> void:
	_refresh_flow_field()
	var gs = _get_game_state()
	if gs != null:
		for enemy in _enemies:
			if not is_instance_valid(enemy) or not enemy.is_alive() or enemy.is_stunned():
				continue
			if enemy.get_state() not in ["idle", "roam", "search", "return"]:
				continue
			var p: Vector3 = gs.get_position(enemy.char_id)
			var best := ""
			var best_d := INF
			for cid in ["aster", "peris"]:
				if not gs.characters.has(cid):
					continue
				var cp: Vector3 = gs.get_position(cid)
				var d := Vector2(p.x - cp.x, p.z - cp.z).length()
				if d < best_d:
					best_d = d
					best = cid
			if best != "":
				enemy.engage_target(best)
	var sched2 = _get_scheduler()
	if sched2 != null:
		sched2.schedule_after(0.8, _pursuit_director, "chase_pursuit")

## The decline pressure: crossing S4 without Tyreg's help fires the side-corridor wave (canon).
func _decline_watch() -> void:
	var gs = _get_game_state()
	if gs != null and not _tyreg_accepted and not _decline_wave_fired:
		for cid in ["aster", "peris"]:
			if gs.characters.has(cid) and gs.get_position(cid).x > 132.0:
				_decline_wave_fired = true
				_spawn_side_wave()
				break
	var sched = _get_scheduler()
	if sched != null and not _decline_wave_fired:
		sched.schedule_after(1.0, _decline_watch, "chase_decline_watch")

func _spawn_side_wave() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	for i in range(2):
		var eid := "naturalizer_%d" % _wave_count
		_wave_count += 1
		# the SAME pack wiring as every wave (coop-exempt, no stealth detection, flow-field
		# pursuit) — this wave shipping without it made its two members run full cooperative
		# space-time planning and write reservations the party's own plan then fought: the
		# late-chase 0.5-1.2 s spikes, finally pinned by the scheduler profiler
		_spawn_enemy({"id": eid, "class": "naturalizer",
			"pos": Vector3(168.0 + 2.0 * float(i), 0.5, -4.0),
			"speed": NAT_SPEED, "detect": 0.0, "coop_exempt": true,
			"targets": ["aster", "peris"]}, gs)
		_wire_wave_nat(eid)
	_show_note("A second wave, from the side corridor Tyreg would have cleared.", 2.4)

func _wire_wave_nat(eid: String) -> void:
	var nat = _enemy_by_id(eid)
	if nat != null and nat.has_method("add_hesitation_zone"):
		nat.add_hesitation_zone(Vector3(CHELATOR_X, 0, -1.0), 6.5)
		nat.pursuit_direct = true
		nat.pursuit_hop_resolver = _flow_hop

## --- The trench at the throat (the director's beat): uncrossable until the REJECTION — the
## ground-shake of enforcement coming out of the walls drops the conduit gantry across it. The
## way OUT opens exactly when the way home closes; before the scan the course is physically
## sealed (the breaker's stroll dies here, architecturally).
var _bridge_down := false
var _gantry_standing: Node3D
var _gantry_fallen: Node3D

var _trench_applied := false

## The host installs gs.grid AFTER _build_chunk — the pit's blockers apply lazily (first _process
## frame with a live grid), and _set_trench_blocked flips them for the fall/reset.
func _process(_delta: float) -> void:
	if not _trench_applied:
		var gs = _get_game_state()
		if gs != null and gs.grid != null:
			_trench_applied = true
			if not _bridge_down:
				_set_trench_blocked(true)

func _set_trench_blocked(blocked: bool) -> void:
	var gs = _get_game_state()
	if gs == null or gs.grid == null:
		return
	for z in range(14):
		for x in range(104):
			var wx := (float(x) + 0.5) * 1.5
			var wz := (float(z) + 0.5) * 1.5 - 10.5
			if wx > TRENCH_X0 and wx < TRENCH_X1 and absf(wz) < CORRIDOR_HALF_Z:
				if blocked:
					gs.grid.add_dynamic_blocker(Vector2i(x, z), "trench")
				else:
					gs.grid.remove_dynamic_blocker(Vector2i(x, z))

func _build_trench() -> void:
	# the visual pit: a dark recess with edge lips
	_add_box(self, Vector3((TRENCH_X0 + TRENCH_X1) * 0.5, -1.1, 0.0),
		Vector3((TRENCH_X1 - TRENCH_X0) * 0.5, 1.0, CORRIDOR_HALF_Z), Color(0.03, 0.03, 0.045))
	for lip in [TRENCH_X0, TRENCH_X1]:
		_add_box(self, Vector3(lip, 0.06, 0.0), Vector3(0.12, 0.06, CORRIDOR_HALF_Z), Color(0.2, 0.21, 0.24))
	_add_label(self, "SERVICE TRENCH — NO CROSSING", Vector3((TRENCH_X0 + TRENCH_X1) * 0.5, 1.6, 3.2),
		Color(0.6, 0.62, 0.66))
	# the conduit gantry standing beside the trench — the thing the shake brings down
	_gantry_standing = Node3D.new()
	_gantry_standing.name = "TrenchGantry"
	add_child(_gantry_standing)
	_add_box(_gantry_standing, Vector3(TRENCH_X0 + 0.4, 2.6, 4.6), Vector3(0.5, 2.6, 0.5),
		Color(0.3, 0.32, 0.36), Color(0.36, 0.91, 0.5), 0.3)
	_add_box(_gantry_standing, Vector3(TRENCH_X0 + 0.4, 5.0, 4.6), Vector3(1.3, 0.3, 0.7),
		Color(0.26, 0.28, 0.32))
	# the fallen span, hidden until the beat
	_gantry_fallen = Node3D.new()
	_gantry_fallen.name = "TrenchGantryFallen"
	_gantry_fallen.visible = false
	add_child(_gantry_fallen)
	_add_box(_gantry_fallen, Vector3((TRENCH_X0 + TRENCH_X1) * 0.5, 0.12, 0.6),
		Vector3((TRENCH_X1 - TRENCH_X0) * 0.5 + 0.6, 0.14, 1.6), Color(0.3, 0.32, 0.36),
		Color(0.36, 0.91, 0.5), 0.2)

## The shake beat: enforcement tears out of the walls, the gantry drops, the trench is bridged.
func _drop_gantry() -> void:
	if _bridge_down:
		return
	_bridge_down = true
	_set_trench_blocked(false)
	if _gantry_standing != null:
		_gantry_standing.visible = false
	if _gantry_fallen != null:
		_gantry_fallen.visible = true
	_set_preview_step("lockout_gantry_down")
	_show_note("The ground shakes them loose — the conduit gantry crashes across the trench.", 2.6)

## --- S1: the sealable service door ---

func _build_door() -> void:
	var door := _add_interactable(self, "ServiceDoor", "Seal the service door behind you",
		Vector3(DOOR_X, 0, 3.6), "SEAL", "", 0.8, true, 1.5,
		Interactable.InteractableType.INSPECTION, false)
	var slab := _add_box(door, Vector3(0, 1.2, 0), Vector3(0.35, 1.2, 0.5), Color(0.3, 0.33, 0.38),
		Color(0.36, 0.91, 0.5), 0.6)
	_outline_interactable_child(door, slab, "ServiceDoor", 1.5)
	door.interacted.connect(_on_door_sealed)

## Sealing buys the chase's biggest single delay: every pursuer reaching the line is HELD while
## the wave cuts through (a real freeze on the scheduler — and the door never re-opens for you
## either; levers do not regenerate).
func _on_door_sealed() -> void:
	if _door_sealed:
		return
	_door_sealed = true
	_add_box(self, Vector3(DOOR_X, 1.5, 0.0), Vector3(0.3, 1.5, CORRIDOR_HALF_Z), Color(0.22, 0.25, 0.3),
		Color(0.36, 0.91, 0.5), 0.4)
	_set_preview_step("lockout_door_sealed")
	_show_note("The service door slams. They will cut through it.", 2.0)
	_arm_door_hold()

func _arm_door_hold() -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	var gs = _get_game_state()
	if gs != null:
		for enemy in _enemies:
			if not is_instance_valid(enemy) or not enemy.is_alive() or enemy.is_stunned():
				continue
			if _door_held.has(enemy.char_id):
				continue   # one hold per cutter — then they are THROUGH (the lever is spent on them)
			var p: Vector3 = gs.get_position(enemy.char_id)
			if p.x < DOOR_X and DOOR_X - p.x < 3.0:
				enemy.stun(DOOR_HOLD_SECS)
				_door_held[enemy.char_id] = true
	sched.schedule_after(0.5, _arm_door_hold, "chase_door_hold")

## --- S2: the Chelator cluster (protocol hesitation made visible) ---

func _build_chelator() -> void:
	for i in range(5):
		var a := TAU * float(i) / 5.0
		_add_box(self, Vector3(CHELATOR_X + cos(a) * 1.6, 0.35 + 0.12 * float(i % 3), -1.0 + sin(a) * 1.4),
			Vector3(0.5, 0.35, 0.5), Color(0.45, 0.3, 0.18), Color(0.8, 0.45, 0.2), 0.5)
	_add_label(self, "chelator cluster", Vector3(CHELATOR_X, 1.6, -1.0), Color(0.85, 0.6, 0.4))

## --- S3: the junction, the offshoot, Tyreg ---

func _build_offshoot() -> void:
	var gs = _get_game_state()
	_pad_in = PortalPad.new()
	_pad_in.name = "OffshootPadIn"
	_pad_in.configure(gs, Vector3(JUNCTION_X + 1.0, 0, 3.8), Vector3(JUNCTION_X + 2.0, 0, OFFSHOOT_Z),
		1.1, Color(0.55, 0.42, 0.98))
	_pad_in.set_group_provider(_selected_party_ids)
	add_child(_pad_in)
	_register_interactable(_pad_in)
	_portals.append(_pad_in)
	_pad_out = PortalPad.new()
	_pad_out.name = "OffshootPadOut"
	_pad_out.configure(gs, Vector3(JUNCTION_X + 6.5, 0, OFFSHOOT_Z), Vector3(OFFSHOOT_EXIT_X, 0, 2.0),
		1.1, Color(0.55, 0.42, 0.98))
	_pad_out.set_group_provider(_selected_party_ids)
	add_child(_pad_out)
	_register_interactable(_pad_out)
	_portals.append(_pad_out)
	# the two tight-hides inside the pocket (capacity one each — the canon split)
	var cap_a := Capbage.new()
	cap_a.name = "PocketHideA"
	cap_a.configure(gs, Vector3(JUNCTION_X + 1.6, 0, OFFSHOOT_Z + 1.6), 1.2)
	add_child(cap_a)
	_register_interactable(cap_a)
	_capbages.append(cap_a)
	var cap_b := Capbage.new()
	cap_b.name = "PocketHideB"
	cap_b.configure(gs, Vector3(JUNCTION_X + 4.2, 0, OFFSHOOT_Z - 1.6), 1.2)
	add_child(cap_b)
	_register_interactable(cap_b)
	_capbages.append(cap_b)
	# the SEAL verbs: a carried bloom spent at a pad stuns it (the double-seal choreography, v1)
	_build_seal_point("SealPadIn", _pad_in)
	_build_seal_point("SealPadOut", _pad_out)
	_arm_portal_follow()

func _build_seal_point(seal_name: String, pad: PortalPad) -> void:
	var seal := _add_interactable(self, seal_name, "Spend a hushbloom to stun the portal",
		(pad.position as Vector3) + Vector3(0.0, 0.0, -1.4), "SEAL", "", 0.6, false, 1.4,
		Interactable.InteractableType.INSPECTION, false)
	var bud := _add_box(seal, Vector3(0, 0.3, 0), Vector3(0.14, 0.3, 0.14), Color(0.5, 0.46, 0.6),
		Color(0.82, 0.74, 0.95), 0.5)
	_outline_interactable_child(seal, bud, seal_name, 1.4)
	seal.interacted.connect(func() -> void:
		if _bloom_carry <= 0:
			_show_note("Nothing in hand to spend.", 1.4)
			return
		_bloom_carry -= 1
		pad.stun(SEAL_SECS)
		_set_preview_step("lockout_pad_sealed")
		_show_note("The bloom bursts against the frame. The portal chokes shut.", 2.0))

## Pursuit follows through OPEN portals (why the double-seal matters): a pursuer near a pad whose
## target just vanished ports after a beat — unless the pad is stunned.
func _arm_portal_follow() -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	var gs = _get_game_state()
	if gs != null:
		for enemy in _enemies:
			if not is_instance_valid(enemy) or not enemy.is_alive() or enemy.is_stunned():
				continue
			if enemy.get_state() != "search" and enemy.get_state() != "pursuit":
				continue
			var p: Vector3 = gs.get_position(enemy.char_id)
			var party_in_pocket := false
			for cid in ["aster", "peris"]:
				if gs.characters.has(cid) and absf(gs.get_position(cid).z - OFFSHOOT_Z) < 3.0:
					party_in_pocket = true
			# the pocket is grid-disconnected: a pursuer whose quarry vanished through the pad
			# WALKS TO the pad (pursuit toward an unreachable cell moves nobody), then ports
			if party_in_pocket and absf(p.z - OFFSHOOT_Z) > 3.0 and _pad_in != null and not _pad_in.is_stunned():
				var pp: Vector3 = _pad_in.position
				var d := Vector2(p.x - pp.x, p.z - pp.z).length()
				if d < 1.6:
					gs.snap_character_to(enemy.char_id, _pad_in._dest)
				elif d < 26.0:
					gs.command_move_to_pos(enemy.char_id, pp)
	# EGRESS: a pursuer inside the pocket with nothing it can hunt (everyone hidden or gone)
	# ports back to the corridor once the entrance wakes — nobody camps a dead end forever
	if gs != null:
		for enemy2 in _enemies:
			if not is_instance_valid(enemy2) or not enemy2.is_alive() or enemy2.is_stunned():
				continue
			var ep: Vector3 = gs.get_position(enemy2.char_id)
			if absf(ep.z - OFFSHOOT_Z) > 3.0:
				continue
			if enemy2.get_state() in ["search", "return", "idle"] and _pad_in != null and not _pad_in.is_stunned():
				gs.snap_character_to(enemy2.char_id, _pad_in.position)
	sched.schedule_after(1.0, _arm_portal_follow, "chase_portal_follow")

func _build_tyreg_junction() -> void:
	var tyreg := _add_interactable(self, "TyregChoice", "Tyreg offers her Suppress for the run",
		Vector3(JUNCTION_X + 2.0, 0, -3.8), "ACCEPT HER HELP", "", 0.8, true, 1.6,
		Interactable.InteractableType.INSPECTION, false)
	var figure := _add_box(tyreg, Vector3(0, 0.9, 0), Vector3(0.3, 0.9, 0.3), Color(0.86, 0.88, 0.92),
		Color(0.72, 0.84, 1.0), 0.8)
	_outline_interactable_child(tyreg, figure, "TyregChoice", 1.6)
	tyreg.interacted.connect(_on_tyreg_accepted)

var _suppress_charges := 0

func _on_tyreg_accepted() -> void:
	if _tyreg_accepted:
		return
	_tyreg_accepted = true
	_suppress_charges = SUPPRESS_CHARGES
	_set_preview_step("lockout_tyreg_accepted")
	_show_note("Tyreg falls in. Low on ammo — she makes each round count.", 2.4)
	_arm_suppress()

## Tyreg's escort (v1): each charge freezes the nearest pursuer that closes on the party. The
## full temporarily-controllable member + ammo-run loop is the follow-up (docs/LOCKOUT_CHASE.md).
func _arm_suppress() -> void:
	var sched = _get_scheduler()
	if sched == null or _suppress_charges <= 0:
		return
	var gs = _get_game_state()
	if gs != null:
		var best = null
		var best_d := 12.0
		for enemy in _enemies:
			if not is_instance_valid(enemy) or not enemy.is_alive() or enemy.is_stunned():
				continue
			var p: Vector3 = gs.get_position(enemy.char_id)
			for cid in ["aster", "peris"]:
				if not gs.characters.has(cid):
					continue
				var cp: Vector3 = gs.get_position(cid)
				var d := Vector2(p.x - cp.x, p.z - cp.z).length()
				if d < best_d:
					best_d = d
					best = enemy
		if best != null and best_d < 6.0:
			best.stun(SUPPRESS_SECS)
			_suppress_charges -= 1
			_show_note("Suppressed. %d rounds left." % _suppress_charges, 1.4)
	sched.schedule_after(1.2, _arm_suppress, "chase_suppress")

## The first escalation rung (framework: warning -> damage -> caught): a pursuer breathing down
## your neck announces itself once per beat — the strike itself stays the enemy's own FSM.
func _close_call_watch() -> void:
	var gs = _get_game_state()
	var sched = _get_scheduler()
	if gs != null and sched != null:
		var t := float(sched.get_current_tick())
		if t - _last_close_call > 8.0:
			for enemy in _enemies:
				if not is_instance_valid(enemy) or not enemy.is_alive() or enemy.is_stunned():
					continue
				var p: Vector3 = gs.get_position(enemy.char_id)
				for cid in ["aster", "peris"]:
					if not gs.characters.has(cid) or gs.is_at_shelter(cid):
						continue
					var cp: Vector3 = gs.get_position(cid)
					if Vector2(p.x - cp.x, p.z - cp.z).length() < CLOSE_CALL_RANGE:
						_last_close_call = t
						_show_note("Right behind you—", 1.2)
						break
				if _last_close_call == t:
					break
	if sched != null:
		sched.schedule_after(1.0, _close_call_watch, "chase_close_call")

## F2: a wipe resets THE CHASE, not just the party — waves despawn, the timeline re-arms, and the
## scanner waits again. Respawning four steps from live pursuers was the probe's alt-F4 moment.
func _restart_fragment() -> void:
	# The first rally sits before the first checkpoint, so a from-the-top wipe can happen while its
	# timed work is live. Retract that work before either reset branch; reset() alone re-enables an
	# Interactable but deliberately does not cancel its FSM callback.
	_cancel_rally_dwells()
	if _chase_started and _checkpoint_x > 0.0:
		_checkpoint_resume()
		return
	var sched = _get_scheduler()
	if sched != null:
		for tag in ["chase_wave_1", "chase_wave_2", "chase_decline_watch", "chase_close_call",
				"chase_pursuit", "chase_portal_follow", "chase_door_hold", "chase_suppress", "chase_directive",
				"chase_hazards", LOCKOUT_RALLY_TICK_TAG]:
			sched.cancel_tag(tag)
	for enemy in _enemies:
		if is_instance_valid(enemy):
			# queue_free is deferred; retract the enemy FSM now so a same-frame Web
			# scheduler advance cannot dispatch through a node being torn down.
			if sched != null:
				sched.cancel_tag("enemy_%s" % enemy.name)
			var gs = _get_game_state()
			if gs != null and gs.characters.has(enemy.char_id):
				gs.unregister_character(enemy.char_id)
			enemy.queue_free()
	_enemies.clear()
	_enemy_posts.clear()
	_chase_started = false
	_pursuit_armed = false
	_decline_wave_fired = false
	if _bridge_down:
		_bridge_down = false
		_set_trench_blocked(true)
		if _gantry_standing != null:
			_gantry_standing.visible = true
		if _gantry_fallen != null:
			_gantry_fallen.visible = false
	_door_held.clear()
	_barricade_wait.clear()
	for wch in _channels:
		if is_instance_valid(wch) and wch.has_method("clear_sweep_refractory"):
			wch.clear_sweep_refractory()
	_trip_refractory.clear()
	_fallen.clear()
	_wave_count = 0
	# from the top means FROM THE TOP: the boundary scanner re-arms so tags can be presented
	# again (a spent one-shot left the whole run unstartable after a full wipe)
	var scanner: Node = find_child("BoundaryScanner", true, false)
	if scanner != null and scanner.has_method("reset"):
		scanner.call("reset")
	super._restart_fragment()
	_restore_pair_after_reset(fragment.spawns if fragment != null else {})
	_reset_rally_progress()
	_show_note("Quiet again. The scanner waits. So do they.", 2.4)

## S1: the record hall terminal banks (the stacks quote) -- visual bodies over the blocked
## cells: dark rows with terminal-green screen strips, the data district's furniture.
func _build_terminal_rows() -> void:
	for bank in [[26.25, -3.0, 7.6], [35.25, 3.0, 7.6]]:
		var bx := float((bank as Array)[0])
		var bz := float((bank as Array)[1])
		var half_z := float((bank as Array)[2]) * 0.5
		_add_box(self, Vector3(bx, 0.8, bz), Vector3(2.2, 0.8, half_z), Color(0.13, 0.14, 0.17))
		for i in range(3):
			_add_box(self, Vector3(bx, 1.15, bz - half_z + (float(i) + 0.5) * half_z * 0.66),
				Vector3(2.0, 0.24, 0.06), Color(0.16, 0.4, 0.24), Color(0.36, 0.91, 0.5), 1.6)
	_add_label(self, "RECORDS -- DO NOT REMOVE", Vector3(30.0, 2.6, 0.0), Color(0.6, 0.72, 0.66))

## S5: the collapse shelf's debris barricade + the slow exposed CLAMBER over it (the approved
## terrain break: cross by climbing what fell). Pursuers funnel over it on a stagger (below).
var _clamber: CrawlTunnel
var _barricade_wait := {}   # pursuer id -> the tick its clamber completes

func _build_barricade() -> void:
	var mid := (BARRICADE_X0 + BARRICADE_X1) * 0.5
	for i in range(9):
		var rz := -CORRIDOR_HALF_Z + (float(i) + 0.5) * (CORRIDOR_HALF_Z * 2.0 / 9.0)
		_add_box(self, Vector3(mid + (0.5 if i % 2 == 0 else -0.4), 0.5 + 0.35 * float(i % 3), rz),
			Vector3(1.4, 0.5 + 0.3 * float(i % 3), 0.7), Color(0.16, 0.15, 0.17))
	_add_label(self, "SHELF COLLAPSE", Vector3(mid, 3.0, 3.4), Color(0.62, 0.58, 0.55))
	_clamber = CrawlTunnel.new()
	_clamber.name = "ClamberBarricade"
	_clamber.description = "Clamber over the collapsed shelf"
	_clamber.tutorial_label = "CLAMBER"
	_clamber.configure(_get_game_state(), Vector3(BARRICADE_X0 - 1.2, 0, 0),
		[Vector3(mid, 1.3, 0.0), Vector3(BARRICADE_X1 + 1.4, 0, 0)], 1.4, 2.2)
	_clamber.set_group_provider(_selected_party_ids)
	_clamber.requirement = _pair_boost_ok
	_clamber.refused.connect(func() -> void:
		_show_note("Too high alone -- one boosts, one pulls up from the top.", 2.6))
	add_child(_clamber)
	_register_interactable(_clamber)
	var stub := _add_box(_clamber, Vector3(-0.6, 0.3, 0.9), Vector3(0.24, 0.6, 0.24), Color(0.32, 0.36, 0.42))
	_outline_interactable_child(_clamber, stub, "ClamberBarricade", 1.4)

## The pinch points: squeeze walls with one body-width gap -- institutional crowd rails gone
## narrow. The party files through; the pack pays (below).
var _trip_refractory := {}   # pursuer id -> next allowed trip tick
var _fallen := {}            # pursuer id -> true while prone (cosmetic tip + climb obstacle)

func _build_pinches() -> void:
	for pin in PINCHES:
		var px := float((pin as Array)[0])
		var gz := float((pin as Array)[1])
		for side in [-1.0, 1.0]:
			var edge := float(side) * CORRIDOR_HALF_Z
			var wall_from := gz + float(side) * (PINCH_GAP_HALF + 0.1)
			if absf(edge - wall_from) < 0.3:
				continue
			var mid_z := (edge + wall_from) * 0.5
			var half_len := absf(edge - wall_from) * 0.5
			_add_box(self, Vector3(px, 1.1, mid_z), Vector3(0.7, 1.1, half_len), Color(0.18, 0.19, 0.22))
			_add_box(self, Vector3(px, 2.3, mid_z), Vector3(0.5, 0.12, half_len), Color(0.36, 0.91, 0.5) * 0.4,
				Color(0.36, 0.91, 0.5), 0.7)
		_add_label(self, "FLOW CONTROL", Vector3(px, 3.0, gz), Color(0.6, 0.72, 0.66))

## The trip-and-pile rule (in the hazard poll): a pursuer entering a pinch at pack speed TRIPS
## prone (an obstacle); the next pursuers CLIMB the pile at a per-body delay. The party threads
## clean -- the pinch is the crowd's governor, not the runner's.
func _pinch_rule(gs, now: float) -> void:
	for pin in PINCHES:
		var px := float((pin as Array)[0])
		var gz := float((pin as Array)[1])
		# count the pile first
		var pile := 0
		for enemy in _enemies:
			if not is_instance_valid(enemy) or not enemy.is_alive():
				continue
			if _fallen.has(enemy.char_id) and enemy.is_stunned():
				var fp: Vector3 = gs.get_position(enemy.char_id)
				if absf(fp.x - px) < 2.0 and absf(fp.z - gz) < 2.0:
					pile += 1
		for enemy2 in _enemies:
			if not is_instance_valid(enemy2) or not enemy2.is_alive() or enemy2.is_stunned():
				continue
			var ep: Vector3 = gs.get_position(enemy2.char_id)
			if absf(ep.x - px) > 1.4 or absf(ep.z - gz) > PINCH_GAP_HALF + 0.4:
				continue
			if not gs.is_moving(enemy2.char_id):
				continue
			if now < float(_trip_refractory.get(enemy2.char_id, -100.0)):
				continue
			_trip_refractory[enemy2.char_id] = now + TRIP_REFRACTORY
			if pile == 0:
				# the first through at speed goes DOWN -- prone, an obstacle
				_fallen[enemy2.char_id] = true
				enemy2.stun(TRIP_SECS)
				pile += 1
			else:
				# the pack behind climbs the pile: a per-body toll, no new obstacle
				enemy2.stun(minf(CLIMB_SECS * float(pile), 4.5))

## @rendering_only -- prone bodies tip over while stunned, right themselves on recovery.
func _sync_fallen_visuals() -> void:
	for id_v in _fallen.keys().duplicate():
		var id := str(id_v)
		var nat = _enemy_by_id(id)
		if nat == null or not is_instance_valid(nat):
			_fallen.erase(id)
			continue
		if nat.is_stunned():
			(nat as Node3D).rotation.z = 1.35
		else:
			(nat as Node3D).rotation.z = 0.0
			_fallen.erase(id)

## THE HAZARD POLL (scheduler cadence): pursuers stuck at the barricade CLAMBER over on a
## stagger -- the funnel is the terrain's price for them too. The WASH's sweep (party knocked
## back + pay hp, fail-forward; pursuers tumbled + stunned: the wash reads tells for nobody)
## is the Channel kit object's OWN behavior -- the chunk only names the policy in
## _wire_wash_sweep (P-KIT).
func _wire_wash_sweep() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	var dest := func(_id: String, p: Vector3) -> Vector3:
		return Vector3(maxf(p.x - 4.5, TRENCH_X1 + 1.0), 0.0, p.z)
	var resolver := func(eid: String):
		return _enemy_by_id(eid)
	var noter := func(_id: String) -> void:
		_show_note("The wash takes your feet -- swept back.", 1.6)
	for ch in _channels:
		if is_instance_valid(ch) and ch.has_method("set_sweep"):
			ch.set_sweep(gs, ["aster", "peris"], dest,
				{"party_hp": 6.0, "enemy_stun": 2.5, "refractory": 4.0,
				"enemy_resolver": resolver, "on_swept": noter})

func _hazard_poll() -> void:
	var gs = _get_game_state()
	var sched = _get_scheduler()
	if gs != null and sched != null:
		var now := float(sched.get_current_tick())
		_pinch_rule(gs, now)
		_sync_fallen_visuals()
		_advance_checkpoint(gs)
		if _enforce_pair_boundary(gs):
			# down_character emits the full-wipe signal. The inherited restart fires in 1.5s
			# and re-arms this poll from either the last checkpoint or the scanner.
			return
		# barricade funnel: a pursuer at the wall whose quarry is beyond clambers after a beat
		for enemy in _enemies:
			if not is_instance_valid(enemy) or not enemy.is_alive() or enemy.is_stunned():
				continue
			var ep: Vector3 = gs.get_position(enemy.char_id)
			if ep.x < BARRICADE_X0 - 4.0 or ep.x > BARRICADE_X0:
				continue
			var quarry_beyond := false
			for cid in ["aster", "peris"]:
				if gs.characters.has(cid) and gs.get_position(cid).x > BARRICADE_X1:
					quarry_beyond = true
			if not quarry_beyond:
				continue
			if not _barricade_wait.has(enemy.char_id):
				_barricade_wait[enemy.char_id] = now + 4.0
			elif now >= float(_barricade_wait[enemy.char_id]):
				_barricade_wait.erase(enemy.char_id)
				gs.snap_character_to(enemy.char_id, Vector3(BARRICADE_X1 + 1.6, 0.0, ep.z))
	if sched != null:
		sched.schedule_after(0.5, _hazard_poll, "chase_hazards")

## THE PAIR GATE: the debris shelf is a two-person move -- one boosts, one pulls up -- so both
## Aster and Peris must be up and at (or already over) the shelf to cross. A member beyond the
## barricade counts: they pull from the top. Solo play caps out here.
func _pair_member_present(gs, cid: String) -> bool:
	if not gs.characters.has(cid):
		return false
	if host != null and host.has_method("is_preview_character_present"):
		return bool(host.call("is_preview_character_present", cid))
	return true

func _pair_boost_ok() -> bool:
	var gs = _get_game_state()
	if gs == null:
		return true
	for cid in ["aster", "peris"]:
		if not _pair_member_present(gs, cid) or gs.is_downed(cid):
			return false
		if gs.get_position(cid).x < BARRICADE_X0 - PAIR_NEAR_X:
			return false
	return true

## The marker advances to each section boundary BOTH members have crossed alive -- solo progress
## never moves it, which keeps the checkpoint and the pair law one rule, not two.
func _advance_checkpoint(gs) -> void:
	var best := _checkpoint_x
	for cx_v in CHECKPOINTS:
		var cx := float(cx_v)
		if cx <= best:
			continue
		var both := true
		for cid in ["aster", "peris"]:
			if not _pair_member_present(gs, cid) or gs.is_downed(cid) or gs.get_position(cid).x < cx:
				both = false
				break
		if both:
			best = cx
	if best > _checkpoint_x:
		_checkpoint_x = best
		_show_note("Checkpoint.", 1.4)

## A broken pair cannot continue into the next chase section. Crossing a fail line with exactly
## one conscious member drops the survivor too; the ordinary full-wipe handler then owns the
## checkpoint/full reset. A conscious partner merely lagging behind is never punished.
func _enforce_pair_boundary(gs) -> bool:
	if not _chase_started or _phase == "complete":
		return false
	var survivor := ""
	for cid in ["aster", "peris"]:
		if not _pair_member_present(gs, cid) or gs.is_downed(cid):
			continue
		if survivor != "":
			return false   # both members are still up; separation alone is allowed
		survivor = cid
	if survivor == "":
		return false
	var survivor_x := float(gs.get_position(survivor).x)
	for boundary_v in PAIR_FAIL_BOUNDARIES:
		var boundary := float(boundary_v)
		if boundary <= _checkpoint_x:
			continue
		if survivor_x >= boundary:
			gs.down_character(survivor)
			# A hidden/unregistered partner is absent rather than downed, so the inherited
			# is_party_downed check cannot schedule this reset. Close that path explicitly.
			if fragment != null and not gs.is_party_downed(Array(fragment.party_ids)):
				_schedule_broken_pair_reset(gs, survivor)
			_show_note("The pair is broken. The chase resets.", 2.6)
			return true
	return false

func _schedule_broken_pair_reset(gs, fallen_id: String) -> void:
	_cancel_rally_dwells()
	_wipe_count += 1
	_fall_pos = gs.get_position(fallen_id)
	var sched = _get_scheduler()
	if sched == null:
		_restart_fragment()
		return
	sched.cancel_tag(_restart_tag())
	sched.schedule_after(1.5, _restart_fragment, _restart_tag())

## Restore both authored runners even if story-presence code hid or unregistered one, then put
## control/camera back on the chase pair instead of leaving the checkpoint focused on Endo.
func _restore_pair_after_reset(positions: Dictionary) -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	for cid in ["aster", "peris"]:
		if not positions.has(cid):
			continue
		var restored_by_host := false
		if host != null and host.has_method("restore_preview_character_for_restart"):
			restored_by_host = bool(host.call("restore_preview_character_for_restart", cid, positions[cid]))
		if not restored_by_host and gs.characters.has(cid):
			gs.restore_character(cid)
			gs.snap_character_to(cid, positions[cid])
	if host != null and host.has_method("select_preview_character"):
		for preferred in ["aster", "peris"]:
			if _pair_member_present(gs, preferred) and not gs.is_downed(preferred):
				host.call("select_preview_character", preferred)
				break

## The checkpoint resume: the pair back on their feet at the marker, the pack despawned and
## re-raised behind them after a grace beat, the world kept as it was. The full from-the-top
## reset only happens before the first marker.
func _checkpoint_resume() -> void:
	var gs = _get_game_state()
	var sched = _get_scheduler()
	_cancel_rally_dwells()
	if sched != null:
		for tag in ["chase_wave_1", "chase_wave_2", "chase_decline_watch", "chase_close_call",
				"chase_pursuit", "chase_portal_follow", "chase_door_hold", "chase_suppress",
				"chase_directive", "chase_hazards", LOCKOUT_RALLY_TICK_TAG]:
			sched.cancel_tag(tag)
	for enemy in _enemies:
		if is_instance_valid(enemy):
			if sched != null:
				sched.cancel_tag("enemy_%s" % enemy.name)
			if gs != null and gs.characters.has(enemy.char_id):
				gs.unregister_character(enemy.char_id)
			enemy.queue_free()
	_enemies.clear()
	_enemy_posts.clear()
	_door_held.clear()
	_barricade_wait.clear()
	for wch in _channels:
		if is_instance_valid(wch) and wch.has_method("clear_sweep_refractory"):
			wch.clear_sweep_refractory()
	_trip_refractory.clear()
	_fallen.clear()
	if gs != null:
		_restore_pair_after_reset({
			"aster": Vector3(_checkpoint_x + 1.5, 0.0, -1.0),
			"peris": Vector3(_checkpoint_x + 1.5, 0.0, 1.0),
		})
	_phase = "ready"
	if sched != null:
		sched.schedule_after(5.5, _spawn_wave.bind(2, false, maxf(_checkpoint_x - 18.0, 2.0)), "chase_wave_2")
		sched.schedule_after(1.5, _close_call_watch, "chase_close_call")
		sched.schedule_after(1.0, _hazard_poll, "chase_hazards")
		sched.schedule_after(1.0, _decline_watch, "chase_decline_watch")
	_arm_portal_follow()
	if _rally_phase == "surviving":
		_arm_rally_tick()
	_set_preview_step("lockout_checkpoint")
	_show_note("Back up at the marker. They know where you fell -- move.", 2.8)

## --- S6: Endo's wall (the boundary the institution respects) ---

func _build_endo_wall() -> void:
	var gs = _get_game_state()
	if gs != null and gs.has_method("add_shelter_region"):
		gs.add_shelter_region(Vector2(WALL_X - 2.0, -CORRIDOR_HALF_Z), Vector2(152.0, CORRIDOR_HALF_Z))
	_add_box(self, Vector3(WALL_X + 8.0, 1.8, 0.0), Vector3(0.6, 1.8, CORRIDOR_HALF_Z), Color(0.28, 0.24, 0.2),
		Color(0.95, 0.8, 0.55), 0.5)
	_add_label(self, "MAINTAINED SECTION — E.", Vector3(WALL_X + 4.0, 2.8, 0.0), Color(0.95, 0.8, 0.55))

## The breaker's route (SpiffinBrit): stroll the whole course WITHOUT presenting tags, rest at
## the wall, credits. No — the scene IS the lockout: before the rejection there is nothing to
## flee and nothing to rest off. Endo waves you back toward the checkpoint.
func _on_exit_shelter_rested(it: Node = null) -> void:
	if not _chase_started:
		_show_note("Endo looks up, nods at the checkpoint. Nothing out here for you yet.", 2.6)
		if it != null and it.has_method("reset"):
			it.call("reset")   # the refusal must not spend the one-shot — the real rest comes later
		return
	# THE END GATE NEEDS THE PAIR: both Aster and Peris, up and inside the maintained section, or
	# nobody rests. (Endo never speaks; the refusal is a gesture.)
	var gs = _get_game_state()
	if gs != null:
		for cid in ["aster", "peris"]:
			if not _pair_member_present(gs, cid) or gs.is_downed(cid) \
					or gs.get_position(cid).x < WALL_X - 16.0:
				_show_note("Endo holds up two fingers, then points back down the corridor.", 2.8)
				if it != null and it.has_method("reset"):
					it.call("reset")
				return
	if _rally_completed_stages.size() < LOCKOUT_RALLY_STAGES.size():
		_show_note("Endo counts four pair relays, then points back to the first dark one.", 2.8)
		if it != null and it.has_method("reset"):
			it.call("reset")
		return
	super._on_exit_shelter_rested(it)

func get_preview_state() -> Dictionary:
	var st: Dictionary = super.get_preview_state()
	st["chase_started"] = _chase_started
	st["pursuit_armed"] = _pursuit_armed
	st["door_sealed"] = _door_sealed
	st["tyreg_accepted"] = _tyreg_accepted
	st["decline_wave"] = _decline_wave_fired
	st["bloom_carry"] = _bloom_carry
	st["pursuers"] = _enemies.size()
	st["bridge_down"] = _bridge_down
	st["checkpoint_x"] = _checkpoint_x
	st["rally_stage_index"] = _rally_stage_index
	st["rally_phase"] = _rally_phase
	st["rally_elapsed_seconds"] = _rally_elapsed
	st["rally_elapsed_by_stage"] = _rally_elapsed_by_stage.duplicate(true)
	st["rally_choices"] = _rally_choices.duplicate(true)
	st["rally_completed_stages"] = _rally_completed_stages.keys().duplicate()
	st["rally_completed_actions"] = _rally_completed_actions.keys().duplicate()
	st["rally_history"] = _rally_history.duplicate(true)
	# the roguelite presenter's descent poll reads the generated-level key; the chase's wall rest
	# IS its shelter rest
	st["shelter_rested"] = bool(st.get("complete", false))
	return st

func get_decoration_audit() -> Dictionary:
	return _decoration_audit.duplicate(true)

## Standardized canonical pacing contract. The new contribution is derived from live node counts,
## authored work dwells, an exact shortest route through each role/strategy layout, and the live
## survival floor. The older 113.5 / 316.5 measurement remains explicitly marked as inherited.
func get_playtime_contract() -> Dictionary:
	var routes := _modeled_rally_route_breakdown()
	var stage_count := LOCKOUT_RALLY_STAGES.size()
	var added_active := float(stage_count) * LOCKOUT_RALLY_STAGE_FLOOR_SECONDS
	var meaningful_active := LOCKOUT_EXISTING_ACTIVE_SECONDS + added_active
	var total_play := LOCKOUT_EXISTING_TOTAL_SECONDS + added_active - LOCKOUT_OVERLAPPED_PRESENTATION_SECONDS
	var local_route_seconds := float(routes.get("shortest_route_seconds", 0.0))
	var specialist_seconds := float(stage_count) * 6.0 * LOCKOUT_RALLY_WORK_SECONDS
	var strategy_seconds := float(stage_count) * LOCKOUT_RALLY_WORK_SECONDS
	var branch_seconds := float(stage_count) * 2.0 * LOCKOUT_RALLY_WORK_SECONDS
	var live_evasion_seconds := float(stage_count) * LOCKOUT_RALLY_LIVE_SECONDS \
		- specialist_seconds - strategy_seconds - branch_seconds - local_route_seconds
	var category_seconds := {
		"existing_escape_traversal": 68.0,
		"existing_lever_execution": 45.5,
		"pair_relay_entry_and_commit": float(stage_count) * 2.0 * LOCKOUT_RALLY_WORK_SECONDS,
		"specialist_fieldwork": specialist_seconds,
		"spatial_strategy_decisions": strategy_seconds,
		"persistent_branch_execution": branch_seconds,
		"local_repositioning": local_route_seconds,
		"live_pressure_evasion": live_evasion_seconds,
	}
	var active_ratio := meaningful_active / maxf(total_play, 0.001)
	return {
		"contract_id": "lockout_active_pacing_v1",
		"target_id": "lockout",
		"target_min_seconds": 300.0,
		"target_max_seconds": 480.0,
		"required_first_clear_seconds": 300.0,
		"modeled_first_clear_seconds": total_play,
		"modeled_meaningful_active_seconds": meaningful_active,
		"meaningful_active_seconds": meaningful_active,
		"total_play_seconds": total_play,
		"active_ratio": active_ratio,
		"meaningful_active_ratio": active_ratio,
		"max_dead_gap_seconds": LOCKOUT_EXISTING_MAX_DEAD_GAP_SECONDS,
		"max_single_mode_seconds": maxf(LOCKOUT_EXISTING_MAX_SINGLE_MODE_SECONDS,
			float(routes.get("max_pressure_evasion_seconds", 0.0))),
		"decision_count": 5,
		"branch_count": 10,
		"category_seconds": category_seconds,
		"hard_idle_lock_seconds": 0.0,
		"measured_existing_meaningful_active_seconds": LOCKOUT_EXISTING_ACTIVE_SECONDS,
		"measured_existing_total_play_seconds": LOCKOUT_EXISTING_TOTAL_SECONDS,
		"existing_measurement_status": "inherited_human_playtest_baseline",
		"measured_new_meaningful_active_seconds": added_active,
		"modeled_added_elapsed_seconds": added_active - LOCKOUT_OVERLAPPED_PRESENTATION_SECONDS,
		"overlapped_nonblocking_presentation_seconds": LOCKOUT_OVERLAPPED_PRESENTATION_SECONDS,
		"rally_stage_count": stage_count,
		"rally_stage_floor_seconds": LOCKOUT_RALLY_STAGE_FLOOR_SECONDS,
		"rally_live_seconds_each": LOCKOUT_RALLY_LIVE_SECONDS,
		"rally_work_seconds_each": LOCKOUT_RALLY_WORK_SECONDS,
		"mandatory_pair_checks": stage_count * 11,
		"mandatory_specialist_actions": stage_count * 6,
		"mandatory_strategy_choices": stage_count,
		"mandatory_branch_actions": stage_count * 2,
		"shortest_rally_route_meters": float(routes.get("shortest_route_meters", 0.0)),
		"shortest_rally_route_seconds": local_route_seconds,
		"rally_route_breakdown": routes,
		"driver_hooks": get_lockout_driver_hooks(),
		"model_note": "The four live clocks advance only while the intact pair is in its sector and moving, performing timed work, or evading an unstunned nearby pursuer. Eight seconds of non-blocking directives overlap sector work instead of extending elapsed time. Dialogue reading, refusal notes, failed routes, deaths, and checkpoint retries count zero toward the clean first-clear claim.",
	}

func _modeled_rally_route_breakdown() -> Dictionary:
	var stage_routes := {}
	var total_meters := 0.0
	var total_seconds := 0.0
	var max_pressure_evasion := 0.0
	for stage_variant in LOCKOUT_RALLY_STAGES:
		var stage: Dictionary = stage_variant
		var stage_id := str(stage.get("id", ""))
		var strategy_routes := {}
		var shortest_strategy := ""
		var shortest_meters := INF
		var shortest_seconds := INF
		var shortest_interior_work := 0.0
		for strategy_variant in (stage.get("strategies", []) as Array):
			var strategy: Dictionary = strategy_variant
			var strategy_id := str(strategy.get("id", ""))
			var route := _modeled_rally_strategy_route(stage, strategy)
			strategy_routes[strategy_id] = route
			var route_meters := float(route.get("meters", 0.0))
			if route_meters < shortest_meters:
				shortest_strategy = strategy_id
				shortest_meters = route_meters
				shortest_seconds = float(route.get("seconds", 0.0))
				shortest_interior_work = float(route.get("interior_work_seconds", 0.0))
		var pressure_evasion := maxf(0.0, LOCKOUT_RALLY_LIVE_SECONDS - shortest_interior_work - shortest_seconds)
		max_pressure_evasion = maxf(max_pressure_evasion, pressure_evasion)
		total_meters += shortest_meters
		total_seconds += shortest_seconds
		stage_routes[stage_id] = {
			"shortest_strategy": shortest_strategy,
			"shortest_meters": shortest_meters,
			"shortest_seconds": shortest_seconds,
			"pressure_evasion_seconds": pressure_evasion,
			"strategies": strategy_routes,
		}
	return {
		"movement_speed_meters_per_second": LOCKOUT_RALLY_RUN_SPEED,
		"shortest_route_meters": total_meters,
		"shortest_route_seconds": total_seconds,
		"max_pressure_evasion_seconds": max_pressure_evasion,
		"stages": stage_routes,
	}

func _modeled_rally_strategy_route(stage: Dictionary, strategy: Dictionary) -> Dictionary:
	var center: Vector3 = stage.get("center", Vector3.ZERO)
	var start := center + Vector3(-4.2, 0.0, 0.0)
	var finish := center + Vector3(4.2, 0.0, 0.0)
	var points_by_role := {"aster": [], "peris": []}
	for action_variant in (stage.get("common", []) as Array):
		var action: Dictionary = action_variant
		var role := str(action.get("role", ""))
		if points_by_role.has(role):
			(points_by_role[role] as Array).append(center + (action.get("offset", Vector3.ZERO) as Vector3))
	var choice_role := str(strategy.get("role", "aster"))
	if points_by_role.has(choice_role):
		(points_by_role[choice_role] as Array).append(center + (strategy.get("offset", Vector3.ZERO) as Vector3))
	for execution_variant in (strategy.get("executions", []) as Array):
		var execution: Dictionary = execution_variant
		var role := str(execution.get("role", ""))
		if points_by_role.has(role):
			(points_by_role[role] as Array).append(center + (execution.get("offset", Vector3.ZERO) as Vector3))
	var role_meters := {}
	var meters := 0.0
	for role in ["aster", "peris"]:
		var role_distance := _shortest_rally_path_distance(start, finish, points_by_role[role] as Array)
		role_meters[role] = role_distance
		meters += role_distance
	var interior_action_count := (stage.get("common", []) as Array).size() + 1 \
		+ (strategy.get("executions", []) as Array).size()
	return {
		"meters": meters,
		"seconds": meters / LOCKOUT_RALLY_RUN_SPEED,
		"role_meters": role_meters,
		"interior_action_count": interior_action_count,
		"interior_work_seconds": float(interior_action_count) * LOCKOUT_RALLY_WORK_SECONDS,
	}

## Exact open-path TSP for one role: both members enter at the west latch, visit their own
## stations in the best legal order, and regroup at the east commit. Five points is the largest
## role set, so this bitmask dynamic program is tiny and deterministic.
func _shortest_rally_path_distance(start: Vector3, finish: Vector3, points: Array) -> float:
	if points.is_empty():
		return start.distance_to(finish)
	var point_count := points.size()
	var all_mask := (1 << point_count) - 1
	var distances := {}
	for point_index in range(point_count):
		distances[Vector2i(1 << point_index, point_index)] = start.distance_to(points[point_index] as Vector3)
	for mask in range(1, all_mask + 1):
		for last_index in range(point_count):
			var state_key := Vector2i(mask, last_index)
			if not distances.has(state_key):
				continue
			var current_distance := float(distances[state_key])
			for next_index in range(point_count):
				var next_bit := 1 << next_index
				if mask & next_bit:
					continue
				var next_mask := mask | next_bit
				var next_key := Vector2i(next_mask, next_index)
				var candidate := current_distance + (points[last_index] as Vector3).distance_to(points[next_index] as Vector3)
				if candidate < float(distances.get(next_key, INF)):
					distances[next_key] = candidate
	var best := INF
	for last_index in range(point_count):
		var key := Vector2i(all_mask, last_index)
		if distances.has(key):
			best = minf(best, float(distances[key]) + (points[last_index] as Vector3).distance_to(finish))
	return best

func get_lockout_driver_hooks() -> Dictionary:
	var stages: Array = []
	for stage_variant in LOCKOUT_RALLY_STAGES:
		var stage: Dictionary = stage_variant
		var stage_id := str(stage.get("id", ""))
		var common: Array = []
		for action_variant in (stage.get("common", []) as Array):
			var action: Dictionary = action_variant
			common.append({
				"node": "LockoutRally_%s_%s" % [stage_id, str(action.get("id", ""))],
				"role": str(action.get("role", "")),
			})
		var strategies := {}
		for strategy_variant in (stage.get("strategies", []) as Array):
			var strategy: Dictionary = strategy_variant
			var strategy_id := str(strategy.get("id", ""))
			var executions: Array = []
			for execution_variant in (strategy.get("executions", []) as Array):
				var execution: Dictionary = execution_variant
				executions.append({
					"node": "LockoutRally_%s_%s" % [stage_id, str(execution.get("id", ""))],
					"role": str(execution.get("role", "")),
				})
			strategies[strategy_id] = {
				"choice_node": "LockoutRally_%s_choose_%s" % [stage_id, strategy_id],
				"choice_role": str(strategy.get("role", "aster")),
				"execution_nodes": executions,
			}
		stages.append({
			"id": stage_id,
			"center": stage.get("center", Vector3.ZERO),
			"pair_radius": LOCKOUT_RALLY_PAIR_RADIUS,
			"live_seconds": LOCKOUT_RALLY_LIVE_SECONDS,
			"entry_node": "LockoutRally_%s_entry" % stage_id,
			"entry_role": "aster",
			"common_nodes": common,
			"strategies": strategies,
			"commit_node": "LockoutRally_%s_commit" % stage_id,
			"commit_role": "peris",
		})
	return {
		"start_node": "BoundaryScanner",
		"stages": stages,
		"finish_node": "EndoWall",
		"input_contract": "select required role, issue the ordinary interact command, walk to the node, and let the TIMED_ACTION dwell finish",
	}

func _exit_tree() -> void:
	var sched = _get_scheduler()
	if sched != null:
		for tag in ["chase_wave_1", "chase_wave_2", "chase_decline_watch", "chase_close_call",
				"chase_pursuit", "chase_portal_follow", "chase_door_hold", "chase_suppress",
				"chase_directive", "chase_hazards", LOCKOUT_RALLY_TICK_TAG]:
			sched.cancel_tag(tag)
		for enemy in _enemies:
			if is_instance_valid(enemy):
				sched.cancel_tag("enemy_%s" % enemy.name)
	super._exit_tree()
