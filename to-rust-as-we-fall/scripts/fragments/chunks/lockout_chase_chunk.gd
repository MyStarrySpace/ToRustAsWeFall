extends "res://scripts/fragments/chunks/data_fragment_chunk.gd"

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
const PAIR_NEAR_X := 12.0        # how far behind the shelf a boosting partner may stand
const SUPPRESS_CHARGES := 3
const SUPPRESS_SECS := 5.0

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
	if _chase_started and _checkpoint_x > 0.0:
		_checkpoint_resume()
		return
	var sched = _get_scheduler()
	if sched != null:
		for tag in ["chase_wave_1", "chase_wave_2", "chase_decline_watch", "chase_close_call",
				"chase_pursuit", "chase_portal_follow", "chase_door_hold", "chase_suppress", "chase_directive", "chase_hazards"]:
			sched.cancel_tag(tag)
	for enemy in _enemies:
		if is_instance_valid(enemy):
			var gs = _get_game_state()
			if gs != null and gs.characters.has(enemy.char_id):
				gs.unregister_character(enemy.char_id)
			enemy.queue_free()
	_enemies.clear()
	_enemy_posts.clear()
	_chase_started = false
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
	_wash_refractory.clear()
	_trip_refractory.clear()
	_fallen.clear()
	_wave_count = 0
	super._restart_fragment()
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
var _wash_refractory := {}  # body id -> the tick its next sweep is allowed

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

## THE HAZARD POLL (scheduler cadence): the wash SWEEPS anyone standing in the flooding strip
## (party knocked back + pay hp -- fail-forward; pursuers tumbled + stunned: the wash reads
## tells for nobody), and pursuers stuck at the barricade CLAMBER over on a stagger -- the
## funnel is the terrain's price for them too.
func _hazard_poll() -> void:
	var gs = _get_game_state()
	var sched = _get_scheduler()
	if gs != null and sched != null:
		var now := float(sched.get_current_tick())
		for ch in _channels:
			if not is_instance_valid(ch) or not ch.is_flooding():
				continue
			for id_v in gs.characters.keys():
				var id := str(id_v)
				# a refractory beat per body: one sweep per wash encounter, never a death-spiral
				# of sweep -> land in the pack -> re-enter -> re-sweep
				if now < float(_wash_refractory.get(id, -100.0)):
					continue
				var p: Vector3 = gs.get_position(id)
				if not ch.floods_at(p.x, p.z):
					continue
				_wash_refractory[id] = now + 4.0
				var is_party := id in ["aster", "peris"]
				gs.command_stop(id)
				gs.snap_character_to(id, Vector3(maxf(p.x - 4.5, TRENCH_X1 + 1.0), 0.0, p.z))
				if is_party:
					gs.adjust_stat(id, "hp", -6.0)
					_show_note("The wash takes your feet -- swept back.", 1.6)
				else:
					var nat = _enemy_by_id(id)
					if nat != null and nat.has_method("stun"):
						nat.stun(2.5)
		_pinch_rule(gs, now)
		_sync_fallen_visuals()
		_advance_checkpoint(gs)
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
func _pair_boost_ok() -> bool:
	var gs = _get_game_state()
	if gs == null:
		return true
	for cid in ["aster", "peris"]:
		if not gs.characters.has(cid) or gs.is_downed(cid):
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
			if not gs.characters.has(cid) or gs.is_downed(cid) or gs.get_position(cid).x < cx:
				both = false
				break
		if both:
			best = cx
	if best > _checkpoint_x:
		_checkpoint_x = best
		_show_note("Checkpoint.", 1.4)

## The checkpoint resume: the pair back on their feet at the marker, the pack despawned and
## re-raised behind them after a grace beat, the world kept as it was. The full from-the-top
## reset only happens before the first marker.
func _checkpoint_resume() -> void:
	var gs = _get_game_state()
	var sched = _get_scheduler()
	if sched != null:
		for tag in ["chase_wave_1", "chase_wave_2", "chase_decline_watch", "chase_close_call",
				"chase_pursuit", "chase_portal_follow", "chase_door_hold", "chase_suppress",
				"chase_directive", "chase_hazards"]:
			sched.cancel_tag(tag)
	for enemy in _enemies:
		if is_instance_valid(enemy):
			if gs != null and gs.characters.has(enemy.char_id):
				gs.unregister_character(enemy.char_id)
			enemy.queue_free()
	_enemies.clear()
	_enemy_posts.clear()
	_door_held.clear()
	_barricade_wait.clear()
	_wash_refractory.clear()
	_trip_refractory.clear()
	_fallen.clear()
	if gs != null:
		var z := -1.0
		for cid in ["aster", "peris"]:
			if gs.characters.has(cid):
				gs.restore_character(cid)
				gs.snap_character_to(cid, Vector3(_checkpoint_x + 1.5, 0.0, z))
				z += 2.0
	_phase = "ready"
	if sched != null:
		sched.schedule_after(5.5, _spawn_wave.bind(2, false, maxf(_checkpoint_x - 18.0, 2.0)), "chase_wave_2")
		sched.schedule_after(1.5, _close_call_watch, "chase_close_call")
		sched.schedule_after(1.0, _hazard_poll, "chase_hazards")
		sched.schedule_after(1.0, _decline_watch, "chase_decline_watch")
	_arm_portal_follow()
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
			if not gs.characters.has(cid) or gs.is_downed(cid) \
					or gs.get_position(cid).x < WALL_X - 16.0:
				_show_note("Endo holds up two fingers, then points back down the corridor.", 2.8)
				if it != null and it.has_method("reset"):
					it.call("reset")
				return
	super._on_exit_shelter_rested(it)

func get_preview_state() -> Dictionary:
	var st: Dictionary = super.get_preview_state()
	st["chase_started"] = _chase_started
	st["door_sealed"] = _door_sealed
	st["tyreg_accepted"] = _tyreg_accepted
	st["decline_wave"] = _decline_wave_fired
	st["bloom_carry"] = _bloom_carry
	st["pursuers"] = _enemies.size()
	st["bridge_down"] = _bridge_down
	st["checkpoint_x"] = _checkpoint_x
	# the roguelite presenter's descent poll reads the generated-level key; the chase's wall rest
	# IS its shelter rest
	st["shelter_rested"] = bool(st.get("complete", false))
	return st
