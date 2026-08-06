extends "res://scripts/fragments/chunks/data_fragment_chunk.gd"

const LevelDecoratorScript := preload("res://scripts/generation/level_decorator.gd")
const PLAYER_CHARACTER_SCENE := preload("res://scenes/game/player_character.tscn")
const CHASE_AUTHORITY_VERSION := 5
const CHASE_AUTHORITY_KEY := "chunk:lockout_chase"
const LOCKOUT_CONTROL_POSITION_TOLERANCE := 0.05
const SEAL_TX_IDLE := "idle"
const SEAL_TX_RESERVED := "reserved"
const SEAL_TX_ITEM_REMOVED := "item_removed"

## Campaign hosts can use this hand-off to play the rejection beat before the pursuit clock
## starts. Fragment preview keeps the immediate starting-gun behavior by default.
signal tags_rejected

## THE LOCKOUT CHASE (GDD §12.1; corridor spec docs/LOCKOUT_CHASE.md; canon mechanics
## reference-docs/chase_scene_framework.md): the Act 1 climax. The party's tags fail at the
## simulation-boundary checkpoint; Naturalizer waves pursue them back down the corridor to Endo's
## maintained wall. Levers (framework canon: recognizable on first sight, never regenerating):
## the sealable service door, the Chelator cluster's protocol hesitation, a Scarpet run — and
## the UNMARKED offshoot pocket behind a portal pair, whose Hushbloom
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

const DOOR_HOLD_SECS := 7.0      # how long the sealed door resists an active breach
const DOOR_CLOSE_SECS := 0.8
const DOOR_OPEN_SECS := 0.7
const DOOR_PHASE_OPEN := "open"
const DOOR_PHASE_CLOSING := "closing"
const DOOR_PHASE_SEALED := "sealed"
const DOOR_PHASE_BREACHING := "breaching"
const DOOR_PHASE_OPENING := "opening"
const DOOR_PHASE_BREACHED := "breached"
const DOOR_PHASE_TAG := "chase_door_phase"
const DOOR_BLOCKER_ID := "lockout_service_door"
const GANTRY_FALL_SECS := 1.1
const GANTRY_PHASE_STANDING := "standing"
const GANTRY_PHASE_FALLING := "falling"
const GANTRY_PHASE_BRIDGED := "bridged"
const GANTRY_PHASE_TAG := "chase_gantry_phase"
const GANTRY_BRIDGE_Z := 0.6
const GANTRY_BRIDGE_HALF_Z := 1.6
const BARRICADE_ENEMY_CLAMBER_SECS := 4.0
const CLAMBER_APEX_Y := 1.3
const PINCH_CLAMBER_EXIT_X := 2.0
const SEAL_SECS := 22.0          # the Hushbloom portal seal (covers one full search cycle)
const PORTAL_FOLLOW_TRANSIT_SECS := 0.8
const CHASE_RECUR_EPSILON := 0.000001
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
const PAIR_NEAR_X := 3.5         # a boost requires a body at the shelf, not a remote party flag
const SUPPRESS_CHARGES := 3
const SUPPRESS_SECS := 5.0
const TYREG_ID := "tyreg"
const TYREG_STATION := Vector3(JUNCTION_X + 2.0, 0.0, -3.8)
const TYREG_STATION_TOLERANCE := 0.65
const TYREG_INTERACTION_RADIUS := 3.2
const TYREG_ESCORT_FOLLOW_DISTANCE := 3.5
const TYREG_SUPPRESS_RANGE := 11.0
const TYREG_MAGAZINE_TYPE := "suppress_magazine"
const TYREG_MAGAZINE_SOURCE := "lockout_tyreg_suppress_magazine"
const TYREG_PHASE_UNAVAILABLE := "unavailable"
const TYREG_PHASE_SEEDING := "seeding"
const TYREG_PHASE_AVAILABLE := "available"
const TYREG_PHASE_JOINING := "joining"
const TYREG_PHASE_ACCEPTED := "accepted"
const TYREG_PHASES := [
	TYREG_PHASE_UNAVAILABLE,
	TYREG_PHASE_SEEDING,
	TYREG_PHASE_AVAILABLE,
	TYREG_PHASE_JOINING,
	TYREG_PHASE_ACCEPTED,
]
const SUPPRESS_TX_IDLE := "idle"
const SUPPRESS_TX_RESERVING := "reserving"


var _chase_started := false
var _boundary_scanner: Interactable
var _scanner_trigger_consumed := 0
var _door_phase := DOOR_PHASE_OPEN
var _door_phase_start := -1.0
var _door_phase_deadline := -1.0
var _door_breacher := ""
var _service_door: Interactable
var _service_door_slab: MeshInstance3D
var _service_door_cells: Array[Vector2i] = []
var _service_door_grid
var _service_door_topology_blocked := false
var _door_trigger_consumed := 0
var _tyreg_phase := TYREG_PHASE_UNAVAILABLE
var _tyreg_join_actor := ""
var _tyreg_magazine_item_id := ""
var _suppress_transaction := {
	"phase": SUPPRESS_TX_IDLE,
	"source_item_id": "",
	"replacement_item_id": "",
	"charge_id": "",
	"remaining_charge_ids": [],
	"target_id": "",
}
var _tyreg_presenter: CharacterBody3D
var _tyreg_interactable: Interactable
var _decline_wave_fired := false
var _pad_in: PortalPad
var _pad_out: PortalPad
var _seal_trigger_consumed := {} # source data id -> last receipt consumed/retracted
var _seal_transaction := {
	"phase": SEAL_TX_IDLE,
	"source_id": "",
	"source_trigger_count": 0,
	"actor": "",
	"item_id": "",
	"pad_name": "",
	"stun_deadline": -1.0,
}
var _wave_count := 0
var _last_close_call := -100.0
var _checkpoint_x := -1.0
var _defer_pursuit_start := false
var _pursuit_armed := false
var _decoration_audit := {}
var _recurring_epochs := {}       # tag -> first absolute tick in a fixed recurring cadence
var _one_shot_deadlines := {}     # tag -> absolute fire tick
var _one_shot_payloads := {}      # tag -> portable callback arguments
var _restoring_chase_authority := false
var _traversal_signal_game_state

func set_pursuit_start_deferred(deferred: bool) -> void:
	_defer_pursuit_start = deferred
	_publish_chase_authority()

func begin_deferred_pursuit() -> void:
	_arm_chase_pursuit()

func get_scene_title() -> String:
	return "The Lockout Chase"

func _build_chunk() -> void:
	fragment = _chase_fragment()
	super._build_chunk()
	# Establish authored physical authority before any chase submechanism (notably the portal
	# cadence) can publish this chunk's composite record. A record that existed before this build
	# still suppresses seeding, while records published later in this same build cannot masquerade
	# as restored truth.
	_seed_tyreg_authority_if_fresh()
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
	_decoration_audit = LevelDecoratorScript.decorate_profile(self, "lockout", {
		"x0": 0.0,
		"x1": 220.0,
		"width": CORRIDOR_HALF_Z * 2.0,
		"wall_height": 3.2,
		"ground_y": 0.0,
		"spacing": 8.4,
		"seed": 0x10C0A7,
		"signs": ["CIVIC LIMIT", "SERVICE CORRIDOR", "MAINTAINED SECTION  >"],
	})
	_wire_lockout_external_traversal_signals()

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
	# The pocket reaches z=16.4. A 14-row grid ended at z=10.5, so its visible floor was never
	# navigable: portal arrivals could neither walk to a hide nor reach the return receiver.
	var hgrid := 20
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
	_boundary_scanner = _add_interactable(self, "BoundaryScanner", "Present tags at the boundary scanner",
		Vector3(PLAZA_X - 3.0, 0, 0), "PRESENT TAGS", "", 0.8, true, 1.6,
		Interactable.InteractableType.INSPECTION, false)
	var body := _add_box(_boundary_scanner, Vector3(0, 0.8, 0), Vector3(0.3, 0.8, 0.3), Color(0.7, 0.72, 0.75),
		Color(0.36, 0.91, 0.5), 1.4)
	_outline_interactable_child(_boundary_scanner, body, "BoundaryScanner", 1.6)
	_boundary_scanner.set_pre_trigger_validator(
		_validate_lockout_control_trigger.bind("scanner", _boundary_scanner))
	_boundary_scanner.interacted.connect(_on_tags_rejected.bind(_boundary_scanner))

## The trigger: rejection escalates, the waves take the corridor (the timetable, not a leash).
func _on_tags_rejected(source: Node = null) -> bool:
	if source != _boundary_scanner or _chase_started \
			or not _lockout_control_receipt_pending(source, "scanner", _scanner_trigger_consumed):
		return false
	_scanner_trigger_consumed = _lockout_source_trigger_count(source)
	_commit_tags_rejected(true)
	return true


func _commit_tags_rejected(emit_story_signal: bool) -> void:
	if _chase_started:
		return
	_chase_started = true
	_drop_gantry()
	_sync_service_door_presenter()
	_publish_chase_authority()
	_set_preview_step("lockout_rejected")
	_show_note("TAG INCOHERENT // ACCESS DENIED. Concealed positions open behind you.", 3.0)
	if emit_story_signal:
		tags_rejected.emit()
	if _defer_pursuit_start:
		return
	_arm_chase_pursuit()

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
	_schedule_chase_one_shot_after("chase_wave_1", 4.5, "wave",
		{"count": 2, "near_party": false, "base_x_override": -1.0})
	# wave 2 activates from CONCEALED WALL NICHES at the party's own segment (canon: "Naturalizers
	# activate from concealed positions" — not all from the plaza; the corridor itself is hostile)
	_schedule_chase_one_shot_after("chase_wave_2", 14.0, "wave",
		{"count": 2, "near_party": true, "base_x_override": -1.0})
	_arm_chase_recurring("chase_decline_watch", 1.0, _decline_watch, 1.0)
	_arm_chase_recurring("chase_close_call", 1.0, _close_call_watch, 1.5)
	_arm_chase_recurring("chase_hazards", 0.5, _hazard_poll, 1.0)
	_wire_wash_sweep()
	_arm_portal_follow()
	sched.schedule_after(2.2, func() -> void:
		_show_note("RUN. East — Endo keeps the wall past the old corridors.", 2.8), "chase_directive")

	_publish_chase_authority()

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
	_publish_chase_authority()

func _arm_pursuit_director() -> void:
	_arm_chase_recurring("chase_pursuit", 0.8, _pursuit_director, 0.8)

## THE PACK'S SHARED PURSUIT FIELD (crowd memoization): ONE breadth-first distance field for each
## distinct (walkability topology, quarry-cell set), over the walkable grid. The director and every
## enemy callback may ask for freshness, but an unchanged answer is a constant-time cache hit.
## Every pursuer then commits the field's already-resolved waypoints directly — it never turns the
## shared answer back into one A* query per body. Derived state only: deterministic and replay-safe.
var _flow_field := {}          # Vector2i -> int (steps to the nearest quarry)
var _flow_field_cache_key := ""
var _flow_field_rebuild_count := 0
var _flow_field_cache_hit_count := 0
const _FLOW_DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

func _flow_quarry_cells(gs) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var seen := {}
	for cid in ["aster", "peris"]:
		if not gs.characters.has(cid):
			continue
		if gs.is_downed(cid) or gs.is_at_shelter(cid) or gs.is_character_hidden(cid):
			continue
		var cell: Vector2i = gs.grid.world_to_grid(gs.get_position(cid))
		if not seen.has(cell):
			seen[cell] = true
			cells.append(cell)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y)
	return cells


func _flow_cache_key(gs, quarry_cells: Array[Vector2i]) -> String:
	var topology_revision: int = int(gs.grid.get_path_walkability_revision()) \
		if gs.grid.has_method("get_path_walkability_revision") else gs.grid.dynamic_blockers.size()
	var key := "%d:%d" % [int(gs.grid.get_instance_id()), topology_revision]
	for cell in quarry_cells:
		key += ":%d,%d" % [cell.x, cell.y]
	return key


func _flow_mask_walkable(grid, mask: PackedByteArray, cell: Vector2i) -> bool:
	if not grid.is_in_bounds(cell.x, cell.y):
		return false
	var index := cell.y * int(grid.width) + cell.x
	return index >= 0 and index < mask.size() and mask[index] != 0


## Match GridWorld's movement law: diagonals are legal only when both orthogonal shoulders are open.
## The old field admitted diagonal squeezes and then relied on per-enemy A* to silently repair them;
## direct waypoint consumption makes the shared field itself responsible for physical truth.
func _flow_step_walkable(
		grid, mask: PackedByteArray, from_cell: Vector2i, to_cell: Vector2i
	) -> bool:
	if not _flow_mask_walkable(grid, mask, to_cell):
		return false
	var delta := to_cell - from_cell
	if absi(delta.x) > 1 or absi(delta.y) > 1 or delta == Vector2i.ZERO:
		return false
	if delta.x != 0 and delta.y != 0:
		return _flow_mask_walkable(grid, mask, from_cell + Vector2i(delta.x, 0)) \
			and _flow_mask_walkable(grid, mask, from_cell + Vector2i(0, delta.y))
	return true


func _refresh_flow_field(force := false) -> void:
	var gs = _get_game_state()
	if gs == null or gs.grid == null:
		_flow_field.clear()
		_flow_field_cache_key = ""
		return
	var quarry_cells := _flow_quarry_cells(gs)
	var cache_key := _flow_cache_key(gs, quarry_cells)
	if not force and cache_key == _flow_field_cache_key:
		_flow_field_cache_hit_count += 1
		return
	_flow_field_cache_key = cache_key
	_flow_field_rebuild_count += 1
	_flow_field.clear()
	var walkability: PackedByteArray = gs.grid.get_path_walkability_mask(0)
	# Seed from every ENGAGEABLE quarry (mirrors the engage gates:
	# downed/sheltered/hidden break the field).
	var frontier: Array[Vector2i] = []
	for cell in quarry_cells:
		if not _flow_mask_walkable(gs.grid, walkability, cell):
			continue
		_flow_field[cell] = 0
		frontier.append(cell)
	var head := 0
	while head < frontier.size():
		var cur: Vector2i = frontier[head]
		head += 1
		var d: int = int(_flow_field[cur]) + 1
		for dir in _FLOW_DIRS:
			var nxt: Vector2i = cur + dir
			if _flow_field.has(nxt):
				continue
			if not _flow_step_walkable(gs.grid, walkability, cur, nxt):
				continue
			_flow_field[nxt] = d
			frontier.append(nxt)


func _best_flow_neighbor(
		grid, walkability: PackedByteArray, cell: Vector2i
	) -> Vector2i:
	var best := cell
	var best_distance: int = int(_flow_field.get(cell, 1 << 30))
	for dir in _FLOW_DIRS:
		var next: Vector2i = cell + dir
		if not _flow_step_walkable(grid, walkability, cell, next):
			continue
		var next_distance: int = int(_flow_field.get(next, 1 << 30))
		if next_distance < best_distance:
			best_distance = next_distance
			best = next
	return best


## Descend at most two legal cells and return the exact waypoint sequence. No field answer means no
## physical move: hidden quarry and the disconnected portal pocket are handled by the chase's search
## and portal-follow systems, rather than drawing a straight line through a wall.
func _flow_path(from_pos: Vector3, _fallback_target: Vector3) -> Array[Vector3]:
	_refresh_flow_field()
	var gs = _get_game_state()
	var path: Array[Vector3] = []
	if gs == null or gs.grid == null or _flow_field.is_empty():
		return path
	var current: Vector2i = gs.grid.world_to_grid(from_pos)
	if not _flow_field.has(current):
		return path
	var walkability: PackedByteArray = gs.grid.get_path_walkability_mask(0)
	var first := _best_flow_neighbor(gs.grid, walkability, current)
	if first == current:
		return path
	path.append(gs.grid.grid_to_world(first))
	# Two cells per scheduler leg keeps the 0.8-second rescan from starving the stride, while retaining
	# the bend waypoint so explicit movement cannot chord through a terminal bank or pinch wall.
	var second := _best_flow_neighbor(gs.grid, walkability, first)
	if second != first:
		path.append(gs.grid.grid_to_world(second))
	return path


## Compatibility endpoint for probes and older scene wiring. New chase packs consume `_flow_path`
## so a two-cell bend retains its intermediate waypoint.
func _flow_hop(from_pos: Vector3, fallback_target: Vector3) -> Vector3:
	var path := _flow_path(from_pos, fallback_target)
	return path[path.size() - 1] if not path.is_empty() else from_pos


func reset_flow_field_diagnostics() -> void:
	_flow_field_rebuild_count = 0
	_flow_field_cache_hit_count = 0


func _invalidate_flow_field_cache() -> void:
	_flow_field.clear()
	_flow_field_cache_key = ""


func get_flow_field_diagnostics() -> Dictionary:
	return {
		"rebuilds": _flow_field_rebuild_count,
		"cache_hits": _flow_field_cache_hit_count,
		"cells": _flow_field.size(),
	}

func _pursuit_director() -> void:
	_refresh_flow_field()
	var gs = _get_game_state()
	if gs != null:
		for enemy in _enemies:
			if not is_instance_valid(enemy) or not enemy.is_alive() or enemy.is_stunned() \
					or gs.is_external_traversal_active(enemy.char_id):
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
	_arm_chase_recurring("chase_pursuit", 0.8, _pursuit_director, 0.8)

## The decline pressure: crossing S4 without Tyreg's help fires the side-corridor wave (canon).
func _decline_watch() -> void:
	var gs = _get_game_state()
	if gs != null and not _tyreg_help_accepted() and not _decline_wave_fired:
		for cid in ["aster", "peris"]:
			if gs.characters.has(cid) and gs.get_position(cid).x > 132.0:
				_decline_wave_fired = true
				_stop_chase_recurring("chase_decline_watch")
				_spawn_side_wave()
				break
	var sched = _get_scheduler()
	if sched != null and not _decline_wave_fired:
		_arm_chase_recurring("chase_decline_watch", 1.0, _decline_watch, 1.0)

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
	_publish_chase_authority()

func _wire_wave_nat(eid: String) -> void:
	var nat = _enemy_by_id(eid)
	if nat != null and nat.has_method("add_hesitation_zone"):
		nat.add_hesitation_zone(Vector3(CHELATOR_X, 0, -1.0), 6.5)
		nat.pursuit_direct = true
		nat.pursuit_hop_resolver = _flow_hop
		nat.pursuit_path_resolver = _flow_path

## --- The trench at the throat (the director's beat): uncrossable until the REJECTION — the
## ground-shake of enforcement coming out of the walls drops the conduit gantry across it. The
## way OUT opens exactly when the way home closes; before the scan the course is physically
## sealed (the breaker's stroll dies here, architecturally).
var _gantry_phase := GANTRY_PHASE_STANDING
var _gantry_phase_start := -1.0
var _gantry_phase_deadline := -1.0
var _gantry_standing: Node3D

var _trench_applied := false

## The host installs gs.grid AFTER _build_chunk — the pit's blockers apply lazily (first _process
## frame with a live grid), and _set_trench_blocked flips them for the fall/reset.
func _process(_delta: float) -> void:
	_sync_lockout_runtime()


func headless_process(delta: float) -> void:
	super.headless_process(delta)
	_sync_lockout_runtime()


func _sync_lockout_runtime() -> void:
	var gs = _get_game_state()
	if not _restoring_chase_authority \
			and str(_suppress_transaction.get("phase", SUPPRESS_TX_IDLE)) \
				== SUPPRESS_TX_RESERVING \
			and _reconcile_restored_tyreg_authority(true):
		_publish_chase_authority()
	if not _restoring_chase_authority \
			and str(_seal_transaction.get("phase", SEAL_TX_IDLE)) != SEAL_TX_IDLE:
		_finish_seal_transaction()
	if gs != null and gs.grid != null:
		if not _trench_applied:
			_trench_applied = true
			if _gantry_phase != GANTRY_PHASE_BRIDGED:
				_set_trench_blocked(true)
		_apply_service_door_topology()
	_sync_gantry_presenter()
	_sync_service_door_presenter()
	_sync_tyreg_presenter()
	_sync_tyreg_interaction_presenter()

func _set_trench_blocked(blocked: bool) -> void:
	var gs = _get_game_state()
	if gs == null or gs.grid == null:
		return
	for z in range(14):
		for x in range(104):
			var wx := (float(x) + 0.5) * 1.5
			var wz := (float(z) + 0.5) * 1.5 - 10.5
			if wx > TRENCH_X0 and wx < TRENCH_X1 and absf(wz) < CORRIDOR_HALF_Z:
				if blocked or absf(wz - GANTRY_BRIDGE_Z) >= GANTRY_BRIDGE_HALF_Z:
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
	# One hinged span owns both poses. The rejection commits its fall around the west lip; the
	# navigation trench remains closed until this same leaf physically reaches the far side.
	_gantry_standing = Node3D.new()
	_gantry_standing.name = "TrenchGantry"
	_gantry_standing.position = Vector3(TRENCH_X0 - 0.6, 0.18, GANTRY_BRIDGE_Z)
	add_child(_gantry_standing)
	var span_length := TRENCH_X1 - TRENCH_X0 + 1.2
	_add_box(_gantry_standing, Vector3(span_length * 0.5, 0.0, 0.0),
		Vector3(span_length * 0.5, 0.14, GANTRY_BRIDGE_HALF_Z), Color(0.3, 0.32, 0.36),
		Color(0.36, 0.91, 0.5), 0.2)
	_add_box(_gantry_standing, Vector3(0.18, 0.0, 0.0), Vector3(0.18, 0.34, 1.85),
		Color(0.18, 0.2, 0.24), Color(0.36, 0.91, 0.5), 0.35)
	_sync_gantry_presenter()

## The shake beat: enforcement tears out of the walls, the gantry drops, the trench is bridged.
func _drop_gantry() -> void:
	if _gantry_phase != GANTRY_PHASE_STANDING:
		return
	var sched = _get_scheduler()
	if sched == null:
		return
	_gantry_phase = GANTRY_PHASE_FALLING
	_gantry_phase_start = float(sched.get_current_tick())
	_gantry_phase_deadline = _gantry_phase_start + GANTRY_FALL_SECS
	_schedule_chase_one_shot_after(GANTRY_PHASE_TAG, GANTRY_FALL_SECS, "gantry_land", {})
	_set_preview_step("lockout_gantry_falling")
	_show_note("The ground shakes a conduit span loose. It is falling across the trench.", 2.0)
	_sync_gantry_presenter()


func _commit_gantry_landed() -> void:
	if _gantry_phase != GANTRY_PHASE_FALLING:
		return
	_gantry_phase = GANTRY_PHASE_BRIDGED
	_gantry_phase_start = -1.0
	_gantry_phase_deadline = -1.0
	_set_trench_blocked(false)
	_sync_gantry_presenter()
	_set_preview_step("lockout_gantry_down")
	_show_note("The span hits both lips. The way out is physically open.", 1.8)
	_publish_chase_authority()


func _gantry_fall_progress() -> float:
	if _gantry_phase == GANTRY_PHASE_STANDING:
		return 0.0
	if _gantry_phase == GANTRY_PHASE_BRIDGED:
		return 1.0
	if _gantry_phase_deadline <= _gantry_phase_start:
		return 0.0
	return clampf((_get_scheduler_tick() - _gantry_phase_start) \
		/ (_gantry_phase_deadline - _gantry_phase_start), 0.0, 1.0)


func _sync_gantry_presenter() -> void:
	if not is_instance_valid(_gantry_standing):
		return
	var t := _gantry_fall_progress()
	var eased := t * t * (3.0 - 2.0 * t)
	_gantry_standing.rotation = Vector3(0.0, 0.0, lerpf(PI * 0.5, 0.0, eased))


## Every chase control consumes the exact GameState receipt minted by its own nearby physical
## source. The active portrait, a direct helper call, or a manually emitted signal is never a
## substitute for the body that reached the scanner/door. One-shot controls retain monotonic
## trigger counts across full chase restarts; reset clears only their spent latch.
func _validate_lockout_control_trigger(
		source: Node, actor: String, action_id: String, expected_source: Node) -> bool:
	if source != expected_source or source != _lockout_control_source(action_id) \
			or not _lockout_actor_ready_at_source(source, actor):
		return false
	match action_id:
		"scanner":
			return not _chase_started
		"door":
			return _chase_started and _door_phase == DOOR_PHASE_OPEN
	return false


func _lockout_control_source(action_id: String) -> Node:
	match action_id:
		"scanner":
			return _boundary_scanner
		"door":
			return _service_door
	return null


func _lockout_control_receipt_pending(
		source: Node, action_id: String, consumed_count: int) -> bool:
	if source != _lockout_control_source(action_id):
		return false
	var actor := str(source.get("active_character")) if is_instance_valid(source) else ""
	return _validate_lockout_control_trigger(source, actor, action_id, source) \
		and _lockout_consumed_source_receipt(source, actor, consumed_count, true)


func _lockout_consumed_source_receipt(
		source: Node, actor: String, consumed_count: int, require_one_shot: bool) -> bool:
	if not is_instance_valid(source) or actor == "":
		return false
	var gs = _get_game_state()
	var data_id := str(source.get("data_id"))
	if gs == null or data_id == "" or not gs.has_interactable(data_id):
		return false
	var receipt: Dictionary = gs.get_interactable(data_id)
	if int(receipt.get("trigger_count", -1)) != consumed_count + 1 \
			or str(receipt.get("last_trigger_character", "")) != actor \
			or not bool(receipt.get("triggered", false)):
		return false
	if require_one_shot:
		return bool(source.get("one_shot")) and bool(source.get("_used")) \
			and not bool(source.get("interaction_enabled")) \
			and bool(receipt.get("one_shot", false)) \
			and not bool(receipt.get("enabled", true))
	return not bool(source.get("one_shot")) and not bool(receipt.get("one_shot", false))


func _lockout_source_trigger_count(source: Node) -> int:
	var gs = _get_game_state()
	var data_id := str(source.get("data_id")) if is_instance_valid(source) else ""
	if gs == null or data_id == "" or not gs.has_interactable(data_id):
		return -1
	return int(gs.get_interactable(data_id).get("trigger_count", -1))


func _lockout_actor_ready_at_source(source: Node, actor: String) -> bool:
	var gs = _get_game_state()
	if gs == null or not is_instance_valid(source) or not (source is Node3D) \
			or actor not in ["aster", "peris"] or actor not in gs.get_party() \
			or not gs.characters.has(actor) or not gs.is_narratively_available(actor) \
			or gs.is_downed(actor) or gs.is_knocked_down(actor) or gs.is_moving(actor) \
			or gs.is_resting(actor) or gs.is_dodging(actor) or gs.is_endocytosing(actor) \
			or gs.is_external_traversal_active(actor) or gs.is_dragging(actor) \
			or gs.is_field_restoring(actor) or gs.is_pushing(actor):
		return false
	var required_actor := str(source.get("required_character"))
	if required_actor != "" and actor != required_actor:
		return false
	var source_position := _lockout_source_data_position(source)
	var actor_position: Vector3 = gs.get_position(actor)
	return _planar_distance(actor_position, source_position) \
			<= float(source.get("interaction_radius")) + LOCKOUT_CONTROL_POSITION_TOLERANCE \
		and absf(actor_position.y - source_position.y) <= 1.25


func _lockout_source_data_position(source: Node) -> Vector3:
	var gs = _get_game_state()
	var data_id := str(source.get("data_id")) if is_instance_valid(source) else ""
	if gs != null and data_id != "" and gs.has_interactable(data_id):
		var saved_position: Variant = gs.get_interactable(data_id).get("position", Vector3.ZERO)
		if saved_position is Vector3:
			return saved_position
	var world_position := (source as Node3D).global_position \
		if source is Node3D else Vector3.ZERO
	if gs != null and gs.coord_map != null and gs.coord_map.has_method("to_data"):
		return gs.coord_map.to_data(world_position)
	return world_position

## --- S1: the sealable service door ---

func _build_door() -> void:
	_service_door = _add_interactable(self, "ServiceDoor", "Seal the service door behind you",
		Vector3(DOOR_X, 0, 3.6), "SEAL", "", 0.8, true, 1.5,
		Interactable.InteractableType.INSPECTION, false)
	var control_body := _add_box(_service_door, Vector3(0, 1.2, 0),
		Vector3(0.35, 1.2, 0.5), Color(0.3, 0.33, 0.38),
		Color(0.36, 0.91, 0.5), 0.6)
	_outline_interactable_child(_service_door, control_body, "ServiceDoor", 1.5)
	_service_door.set_pre_trigger_validator(
		_validate_lockout_control_trigger.bind("door", _service_door))
	_service_door.interacted.connect(_on_door_sealed.bind(_service_door))
	# The complete leaf always exists. Each phase moves this same physical object; restore never
	# manufactures a proxy slab or makes a committed blocker disappear.
	_service_door_slab = _add_box(self,
		Vector3(DOOR_X, 1.5, _service_door_open_z()),
		Vector3(0.3, 1.5, CORRIDOR_HALF_Z), Color(0.22, 0.25, 0.3),
		Color(0.36, 0.91, 0.5), 0.4, "ServiceDoorSlab") as MeshInstance3D
	_add_box(self, Vector3(DOOR_X, 3.15, 0.0),
		Vector3(0.45, 0.12, CORRIDOR_HALF_Z + 0.35), Color(0.13, 0.15, 0.18),
		Color(0.36, 0.91, 0.5), 0.25, "ServiceDoorTrack")
	_sync_service_door_presenter()

## Sealing buys the chase's biggest single delay. The barrier holds the route, not one enemy's
## stun flag; after a saved breach interval the damaged leaf physically slides out of the path.
func _on_door_sealed(source: Node = null) -> bool:
	if source != _service_door or _door_phase != DOOR_PHASE_OPEN \
			or not _lockout_control_receipt_pending(source, "door", _door_trigger_consumed):
		return false
	_door_trigger_consumed = _lockout_source_trigger_count(source)
	_begin_service_door_close()
	return true


func _begin_service_door_close() -> void:
	if _door_phase != DOOR_PHASE_OPEN:
		return
	_start_door_timed_phase(DOOR_PHASE_CLOSING, DOOR_CLOSE_SECS, "door_close")
	if is_instance_valid(_service_door):
		_service_door.set_interaction_enabled(false)
	_set_preview_step("lockout_door_closing")
	_show_note("The service door is crossing the corridor -- clear the leaf.", 1.8)


func _commit_door_sealed() -> void:
	if _door_phase != DOOR_PHASE_CLOSING:
		return
	_door_phase = DOOR_PHASE_SEALED
	_door_phase_start = -1.0
	_door_phase_deadline = -1.0
	_apply_service_door_topology(true)
	_sync_service_door_presenter()
	_set_preview_step("lockout_door_sealed")
	_show_note("The leaf seats in the track. They will have to cut it open.", 2.0)
	_arm_door_hold()
	_publish_chase_authority()

func _arm_door_hold() -> void:
	if _door_phase != DOOR_PHASE_SEALED:
		_stop_chase_recurring("chase_door_hold")
		return
	var gs = _get_game_state()
	if gs != null:
		for enemy in _enemies:
			if not is_instance_valid(enemy) or not enemy.is_alive() or enemy.is_stunned() \
					or gs.is_external_traversal_active(enemy.char_id):
				continue
			var p: Vector3 = gs.get_position(enemy.char_id)
			if p.x < DOOR_X and DOOR_X - p.x < 3.0:
				_begin_door_breach(str(enemy.char_id))
				return
	_arm_chase_recurring("chase_door_hold", 0.5, _arm_door_hold, 0.5)


func _begin_door_breach(breacher_id: String) -> void:
	if _door_phase != DOOR_PHASE_SEALED:
		return
	_stop_chase_recurring("chase_door_hold")
	_door_breacher = breacher_id
	_start_door_timed_phase(DOOR_PHASE_BREACHING, DOOR_HOLD_SECS, "door_breach")
	_set_preview_step("lockout_door_breaching")
	_show_note("Cutters bite into the seated leaf. The whole pack is held at the barrier.", 2.2)


func _commit_door_breached() -> void:
	if _door_phase != DOOR_PHASE_BREACHING:
		return
	_start_door_timed_phase(DOOR_PHASE_OPENING, DOOR_OPEN_SECS, "door_open")
	_set_preview_step("lockout_door_opening")
	_show_note("The cut track gives. The damaged leaf is being forced aside.", 1.6)


func _commit_door_open() -> void:
	if _door_phase != DOOR_PHASE_OPENING:
		return
	_door_phase = DOOR_PHASE_BREACHED
	_door_phase_start = -1.0
	_door_phase_deadline = -1.0
	_door_breacher = ""
	_apply_service_door_topology(true)
	_sync_service_door_presenter()
	_set_preview_step("lockout_door_breached")
	_publish_chase_authority()


func _start_door_timed_phase(phase_name: String, duration: float, callback_kind: String) -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	_door_phase = phase_name
	_door_phase_start = float(sched.get_current_tick())
	_door_phase_deadline = _door_phase_start + duration
	_schedule_chase_one_shot_after(DOOR_PHASE_TAG, duration, callback_kind, {})
	_apply_service_door_topology()
	_sync_service_door_presenter()


func _service_door_open_z() -> float:
	return CORRIDOR_HALF_Z * 2.2


func _door_transition_progress() -> float:
	if _door_phase_start < 0.0 or _door_phase_deadline <= _door_phase_start:
		return 1.0
	return clampf((_get_scheduler_tick() - _door_phase_start) \
		/ (_door_phase_deadline - _door_phase_start), 0.0, 1.0)


func _door_blocks_corridor() -> bool:
	return _door_phase in [DOOR_PHASE_SEALED, DOOR_PHASE_BREACHING, DOOR_PHASE_OPENING]


func _sync_service_door_presenter() -> void:
	if not is_instance_valid(_service_door_slab):
		return
	var open_z := _service_door_open_z()
	var slab_z := open_z
	match _door_phase:
		DOOR_PHASE_CLOSING:
			slab_z = lerpf(open_z, 0.0, _door_transition_progress())
		DOOR_PHASE_SEALED, DOOR_PHASE_BREACHING:
			slab_z = 0.0
		DOOR_PHASE_OPENING:
			slab_z = lerpf(0.0, open_z, _door_transition_progress())
		DOOR_PHASE_BREACHED, DOOR_PHASE_OPEN:
			slab_z = open_z
	_service_door_slab.position = Vector3(DOOR_X, 1.5, slab_z)
	_service_door_slab.rotation = Vector3.ZERO
	if _door_phase == DOOR_PHASE_BREACHING:
		_service_door_slab.rotation.x = sin(_get_scheduler_tick() * 18.0) * 0.012
	if is_instance_valid(_service_door):
		var gs = _get_game_state()
		var door_receipt: Dictionary = gs.get_interactable(_service_door.data_id) \
			if gs != null and gs.has_interactable(_service_door.data_id) else {}
		var accepted_source_pending := bool(door_receipt.get("one_shot", false)) \
			and bool(door_receipt.get("triggered", false))
		var should_enable := _chase_started and _door_phase == DOOR_PHASE_OPEN \
			and not accepted_source_pending
		if _service_door.is_interaction_enabled() != should_enable:
			_service_door.set_interaction_enabled(should_enable)


func _apply_service_door_topology(force := false) -> void:
	var gs = _get_game_state()
	if gs == null or gs.grid == null:
		return
	var grid = gs.grid
	if _service_door_grid != grid:
		_service_door_grid = grid
		_service_door_cells.clear()
		_service_door_topology_blocked = false
		var door_x: int = grid.world_to_grid(Vector3(DOOR_X, 0.0, 0.0)).x
		for z in range(grid.height):
			var cell := Vector2i(door_x, z)
			if absf(grid.grid_to_world(cell).z) < CORRIDOR_HALF_Z:
				_service_door_cells.append(cell)
	var should_block := _door_blocks_corridor()
	if not force and should_block == _service_door_topology_blocked:
		return
	for cell in _service_door_cells:
		if str(grid.dynamic_blockers.get(cell, "")) == DOOR_BLOCKER_ID:
			grid.remove_dynamic_blocker(cell)
		grid.clear_sight_blocker(cell)
	if should_block:
		for cell in _service_door_cells:
			grid.add_dynamic_blocker(cell, DOOR_BLOCKER_ID)
			grid.add_sight_blocker(cell)
	_service_door_topology_blocked = should_block


func _reset_service_door_for_full_restart() -> void:
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag(DOOR_PHASE_TAG)
	_door_phase = DOOR_PHASE_OPEN
	_door_phase_start = -1.0
	_door_phase_deadline = -1.0
	_door_breacher = ""
	if is_instance_valid(_service_door) and _service_door.has_method("reset"):
		_service_door.reset()
	_apply_service_door_topology(true)
	_sync_service_door_presenter()

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
	PortalFixtures.dress_matching([_pad_in, _pad_out])   # chained pads: contract arches
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
	# The SEAL verbs consume the actual Hushbloom item held by the interacting character. Dropped
	# flowers and blooms carried by the other party member therefore cannot act at a distance.
	# Both controls live inside the pocket: the entry seal is mounted beside the receiver the
	# party arrives at, while the exit seal sits beside the return pad's source. Putting the first
	# control back in the corridor made the advertised "port in, double-seal" solve physically
	# impossible and left direct test hooks as the only way to perform it.
	_build_seal_point("SealPadIn", _pad_in, _pad_in.get_data_destination())
	_build_seal_point("SealPadOut", _pad_out, _pad_out.get_data_source())
	_arm_portal_follow()


func _build_seal_point(
		seal_name: String, pad: PortalPad, control_anchor: Vector3) -> void:
	var control_position := control_anchor + Vector3(0.0, 0.0, -1.4)
	var seal := _add_interactable(self, seal_name, "Spend a hushbloom to stun the portal",
		control_position, "SEAL", "", 0.6, false, 1.4,
		Interactable.InteractableType.INSPECTION, false)
	seal.set_meta("lockout_seal_data_position", control_position)
	seal.set_meta("lockout_seal_pad_name", str(pad.name))
	seal.set_pre_trigger_validator(_validate_seal_interaction.bind(seal, pad))
	var bud := _add_box(seal, Vector3(0, 0.3, 0), Vector3(0.14, 0.3, 0.14), Color(0.5, 0.46, 0.6),
		Color(0.82, 0.74, 0.95), 0.5)
	_outline_interactable_child(seal, bud, seal_name, 1.4)
	seal.interacted.connect(_on_seal_interacted.bind(seal, pad))


func _validate_seal_interaction(
		source: Node, actor_id: String, expected_source: Node, pad: PortalPad) -> bool:
	if source != expected_source or not is_instance_valid(source) \
			or not is_instance_valid(pad) or pad not in [_pad_in, _pad_out] \
			or str(source.get_meta("lockout_seal_pad_name", "")) != str(pad.name) \
			or str(_seal_transaction.get("phase", SEAL_TX_IDLE)) != SEAL_TX_IDLE \
			or pad.is_stunned() or not _lockout_actor_ready_at_source(source, actor_id):
		return false
	return _hand_hushbloom(actor_id) != ""


func _on_seal_interacted(seal: Interactable, pad: PortalPad) -> bool:
	var gs = _get_game_state()
	var actor := str(seal.active_character) if is_instance_valid(seal) else ""
	var source_id := str(seal.data_id) if is_instance_valid(seal) else ""
	var consumed_count := int(_seal_trigger_consumed.get(source_id, 0))
	var item_id := _hand_hushbloom(actor)
	if gs == null or source_id == "" or item_id == "" \
			or not _validate_seal_interaction(seal, actor, seal, pad) \
			or not _lockout_consumed_source_receipt(
				seal, actor, consumed_count, false):
		return false
	# Removing the ordinary item is the spend. PortalPad publishes its own saved stun deadline, so
	# reload sees either an unspent held flower or the paid, sealed portal—never an integer proxy.
	_seal_transaction = {
		"phase": SEAL_TX_RESERVED,
		"source_id": source_id,
		"source_trigger_count": _lockout_source_trigger_count(seal),
		"actor": actor,
		"item_id": item_id,
		"pad_name": str(pad.name),
		"stun_deadline": _get_scheduler_tick() + SEAL_SECS,
	}
	_publish_chase_authority()
	return _finish_seal_transaction()


## Reserve source receipt + exact held item + absolute effect deadline before removing anything.
## On restore, an intact reserved item completes the already-accepted spend; an absent reserved item
## completes the owed portal effect. A wrong-holder/corrupt reservation retracts without minting.
func _finish_seal_transaction() -> bool:
	var phase := str(_seal_transaction.get("phase", SEAL_TX_IDLE))
	if phase not in [SEAL_TX_RESERVED, SEAL_TX_ITEM_REMOVED]:
		return false
	var gs = _get_game_state()
	var source_id := str(_seal_transaction.get("source_id", ""))
	var actor := str(_seal_transaction.get("actor", ""))
	var item_id := str(_seal_transaction.get("item_id", ""))
	var receipt_count := int(_seal_transaction.get("source_trigger_count", 0))
	var pad := _lockout_portal_for_name(str(_seal_transaction.get("pad_name", "")))
	var source := _lockout_seal_source_for_id(source_id)
	var source_receipt: Dictionary = gs.get_interactable(source_id) \
		if gs != null and gs.has_interactable(source_id) else {}
	if gs == null or source_id == "" or actor == "" or receipt_count <= 0 \
			or not is_instance_valid(pad) or not is_instance_valid(source) \
			or receipt_count != int(_seal_trigger_consumed.get(source_id, 0)) + 1 \
			or int(source_receipt.get("trigger_count", -1)) != receipt_count \
			or str(source_receipt.get("last_trigger_character", "")) != actor:
		_retract_seal_transaction_receipt()
		return false
	if gs.items.has(item_id):
		var item: Dictionary = gs.items[item_id]
		if str(item.get("holder", "")) != actor or str(item.get("location", "")) != "hand" \
				or item_id not in gs.get_hand_items(actor) \
				or str(item.get("type", "")) != "hushbloom":
			_retract_seal_transaction_receipt()
			return false
		gs.remove_item(item_id)
		_seal_transaction["phase"] = SEAL_TX_ITEM_REMOVED
		_publish_chase_authority()
	elif phase == SEAL_TX_RESERVED:
		# A snapshot after exact-item removal but before the phase publish still owes the paid effect.
		_seal_transaction["phase"] = SEAL_TX_ITEM_REMOVED

	var remaining := maxf(0.0,
		float(_seal_transaction.get("stun_deadline", _get_scheduler_tick()))
			- _get_scheduler_tick())
	if remaining > 0.0:
		pad.stun(remaining)
	_seal_trigger_consumed[source_id] = maxi(
		int(_seal_trigger_consumed.get(source_id, 0)), receipt_count)
	_clear_seal_transaction()
	_publish_chase_authority()
	_set_preview_step("lockout_pad_sealed")
	_show_note("The held bloom bursts against the frame. The portal chokes shut.", 2.0)
	return true


func _retract_seal_transaction_receipt() -> void:
	var source_id := str(_seal_transaction.get("source_id", ""))
	var receipt_count := maxi(0, int(_seal_transaction.get("source_trigger_count", 0)))
	if source_id != "":
		_seal_trigger_consumed[source_id] = maxi(
			int(_seal_trigger_consumed.get(source_id, 0)), receipt_count)
	_clear_seal_transaction()
	_publish_chase_authority()


func _clear_seal_transaction() -> void:
	_seal_transaction = {
		"phase": SEAL_TX_IDLE,
		"source_id": "",
		"source_trigger_count": 0,
		"actor": "",
		"item_id": "",
		"pad_name": "",
		"stun_deadline": -1.0,
	}


func _lockout_portal_for_name(pad_name: String) -> PortalPad:
	if is_instance_valid(_pad_in) and str(_pad_in.name) == pad_name:
		return _pad_in
	if is_instance_valid(_pad_out) and str(_pad_out.name) == pad_name:
		return _pad_out
	return null


func _lockout_seal_source_for_id(source_id: String) -> Interactable:
	for source_name in ["SealPadIn", "SealPadOut"]:
		var source := find_child(source_name, true, false) as Interactable
		if is_instance_valid(source) and str(source.data_id) == source_id:
			return source
	return null


func _hand_hushbloom(character_id: String) -> String:
	var gs = _get_game_state()
	if gs == null or character_id == "" or not gs.characters.has(character_id):
		return ""
	for item_id_v in gs.get_hand_items(character_id):
		var item_id := str(item_id_v)
		if not gs.items.has(item_id) \
				or str((gs.items[item_id] as Dictionary).get("type", "")) != "hushbloom":
			continue
		var properties: Dictionary = (gs.items[item_id] as Dictionary).get("properties", {})
		var source_key := str(properties.get("source_hushbloom", ""))
		var source_state: Variant = gs.get_world_state(source_key, {}) if source_key != "" else {}
		# A signal-time pickup restore owes one deterministic finalization before the item can pay
		# another mechanism. This prevents spend -> save -> source-regrows transaction chaining.
		if source_state is Dictionary and str((source_state as Dictionary).get("phase", "")) == "picking":
			continue
		return item_id
	return ""


func _carried_hushbloom_count() -> int:
	var gs = _get_game_state()
	if gs == null:
		return 0
	var count := 0
	for cid_v in gs.characters.keys():
		var cid := str(cid_v)
		for item_id_v in gs.get_hand_items(cid):
			var item_id := str(item_id_v)
			if gs.items.has(item_id) \
					and str((gs.items[item_id] as Dictionary).get("type", "")) == "hushbloom":
				count += 1
	return count

## Pursuit follows through OPEN portals (why the double-seal matters): a pursuer near a pad whose
## target just vanished ports after a beat — unless the pad is stunned.
func _arm_portal_follow() -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	var gs = _get_game_state()
	if gs != null:
		for enemy in _enemies:
			if not is_instance_valid(enemy) or not enemy.is_alive() or enemy.is_stunned() \
					or gs.is_external_traversal_active(enemy.char_id):
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
			if party_in_pocket and absf(p.z - OFFSHOOT_Z) > 3.0 \
					and _pad_in != null and not _pad_in.is_stunned():
				var pp: Vector3 = _pad_in.get_data_source()
				var d := Vector2(p.x - pp.x, p.z - pp.z).length()
				if d < 1.6:
					_begin_portal_follow_transit(enemy, false)
				elif d < 26.0:
					gs.command_move_to_pos(enemy.char_id, pp)
	# EGRESS: a pursuer inside the pocket with nothing it can hunt (everyone hidden or gone)
	# walks back to the entrance receiver and reverses through it once the seal wakes. Nobody
	# camps a dead end forever, but the body cannot pop out from arbitrary pocket space.
	if gs != null:
		for enemy2 in _enemies:
			if not is_instance_valid(enemy2) or not enemy2.is_alive() or enemy2.is_stunned() \
					or gs.is_external_traversal_active(enemy2.char_id):
				continue
			var ep: Vector3 = gs.get_position(enemy2.char_id)
			if absf(ep.z - OFFSHOOT_Z) > 3.0:
				continue
			if enemy2.get_state() in ["search", "return", "idle"] \
					and _pad_in != null and not _pad_in.is_stunned():
				var receiver: Vector3 = _pad_in.get_data_destination()
				var receiver_gap := Vector2(ep.x - receiver.x, ep.z - receiver.z).length()
				if receiver_gap < 1.6:
					_begin_portal_follow_transit(enemy2, true)
				elif receiver_gap < 26.0:
					gs.command_move_to_pos(enemy2.char_id, receiver)
	_arm_chase_recurring("chase_portal_follow", 1.0, _arm_portal_follow, 1.0)


func _begin_portal_follow_transit(enemy, reverse: bool) -> bool:
	if not is_instance_valid(enemy) or _pad_in == null:
		return false
	var direction := "return" if reverse else "enter"
	return _pad_in.begin_external_transit(
		str(enemy.char_id), _portal_follow_traversal_id(str(enemy.char_id), direction),
		PORTAL_FOLLOW_TRANSIT_SECS, reverse)


func _portal_follow_traversal_id(char_id: String, direction: String) -> StringName:
	return StringName("lockout_portal_%s:%s" % [direction, char_id])


func _build_tyreg_junction() -> void:
	_build_tyreg_presenter()
	var meshes: Array = []
	if is_instance_valid(_tyreg_presenter):
		var body_mesh := _tyreg_presenter.get_node_or_null("Mesh") as MeshInstance3D
		if body_mesh != null:
			meshes.append(body_mesh)
	_tyreg_interactable = _add_object_interactable(
		self,
		"TyregChoice",
		"Tyreg offers her three physical Suppress rounds for the run",
		TYREG_STATION,
		"ACCEPT HER HELP",
		meshes,
		"",
		0.0,
		false,
		TYREG_INTERACTION_RADIUS,
		Interactable.InteractableType.INSPECTION
	) as Interactable
	if is_instance_valid(_tyreg_interactable):
		_tyreg_interactable.set_meta(
			"interaction_target_position",
			TYREG_STATION + Vector3(-1.5, 0.0, 0.0)
		)
		_tyreg_interactable.consequence_preview = \
			"Tyreg joins the retreat with the rounds visible in her hand"
		_tyreg_interactable.set_pre_trigger_validator(_validate_tyreg_acceptance)
		_tyreg_interactable.interacted.connect(_on_tyreg_interacted)
	_sync_tyreg_presenter()
	_sync_tyreg_interaction_presenter()


## Seed one authored body and one finite magazine only when this chunk has no prior chase authority.
## A restored snapshot replaces GameState after construction; absent/corrupt restored truth is therefore
## never repaired by manufacturing a second Tyreg or another magazine.
func _seed_tyreg_authority_if_fresh() -> void:
	var gs = _get_game_state()
	if gs == null or not gs.has_method("get_world_state"):
		return
	if gs.get_world_state(CHASE_AUTHORITY_KEY, null) is Dictionary:
		return
	if not gs.characters.has(TYREG_ID):
		gs.register_character(TYREG_ID, TYREG_STATION, 3.2, {
			"hp": 100.0,
			"stamina": 100.0,
			"atp": 8.0,
			"narrative_available": true,
		})
	if not _tyreg_body_at_authored_station(gs):
		_tyreg_phase = TYREG_PHASE_UNAVAILABLE
		_publish_chase_authority()
		return
	_tyreg_magazine_item_id = _spawn_item(
		TYREG_MAGAZINE_TYPE,
		TYREG_STATION,
		_tyreg_magazine_properties(_initial_tyreg_charge_ids())
	)
	if _tyreg_magazine_item_id == "":
		_tyreg_phase = TYREG_PHASE_UNAVAILABLE
		_publish_chase_authority()
		return
	# Publish the exact finite identity before pickup emits its synchronous signal. A signal-time save
	# can then finish this seed from the same ground item or recognize it already in Tyreg's hand.
	_tyreg_phase = TYREG_PHASE_SEEDING
	_publish_chase_authority()
	if _pick_up_item(TYREG_ID, _tyreg_magazine_item_id) \
			and _tyreg_owns_exact_magazine(_tyreg_magazine_item_id):
		_tyreg_phase = TYREG_PHASE_AVAILABLE
	else:
		_tyreg_phase = TYREG_PHASE_UNAVAILABLE
	_publish_chase_authority()


func _build_tyreg_presenter() -> void:
	if is_instance_valid(_tyreg_presenter):
		return
	_tyreg_presenter = PLAYER_CHARACTER_SCENE.instantiate() as CharacterBody3D
	if _tyreg_presenter == null:
		return
	var gs = _get_game_state()
	_tyreg_presenter.name = "Tyreg"
	_tyreg_presenter.position = TYREG_STATION
	_tyreg_presenter.set("char_id", TYREG_ID)
	_tyreg_presenter.set("game_state", gs)
	_tyreg_presenter.set("grid_world", gs.grid if gs != null else null)
	_tyreg_presenter.set("color", Color(0.86, 0.88, 0.92))
	var label := _tyreg_presenter.get_node_or_null("Label3D") as Label3D
	if label != null:
		label.text = "TYREG"
		label.modulate = Color(0.86, 0.88, 0.92, 0.82)
	add_child(_tyreg_presenter)
	if _tyreg_presenter.has_method("restore_move_input_enabled"):
		_tyreg_presenter.call("restore_move_input_enabled", false)


## Pure preflight: no UI reset, inventory mutation, party mutation, or authority write may happen here.
## Interactable invokes it before its own GameState trigger signal/one-shot seam.
func _validate_tyreg_acceptance(_interactable: Interactable, actor_id: String) -> bool:
	return _tyreg_acceptance_truth(actor_id, true)


func _tyreg_acceptance_truth(actor_id: String, require_available_phase: bool) -> bool:
	var gs = _get_game_state()
	if gs == null or gs.grid == null:
		return false
	if require_available_phase and _tyreg_phase != TYREG_PHASE_AVAILABLE:
		return false
	if str(_suppress_transaction.get("phase", SUPPRESS_TX_IDLE)) != SUPPRESS_TX_IDLE:
		return false
	if actor_id == "" or not gs.characters.has(actor_id):
		return false
	if actor_id not in gs.get_party():
		return false
	if not gs.is_narratively_available(actor_id) or gs.is_downed(actor_id) \
			or gs.is_knocked_down(actor_id):
		return false
	if not _tyreg_body_at_authored_station(gs) \
			or not gs.is_narratively_available(TYREG_ID) or gs.is_downed(TYREG_ID) \
			or gs.is_knocked_down(TYREG_ID):
		return false
	if not is_instance_valid(_tyreg_presenter) or not _tyreg_presenter.visible:
		return false
	var actor_pos: Vector3 = gs.get_position(actor_id)
	var tyreg_pos: Vector3 = gs.get_position(TYREG_ID)
	if _planar_distance(actor_pos, tyreg_pos) > TYREG_INTERACTION_RADIUS \
			or absf(actor_pos.y - tyreg_pos.y) > 1.25:
		return false
	if not gs.grid.has_line_of_sight(actor_pos, tyreg_pos):
		return false
	return _tyreg_owns_exact_magazine(_tyreg_magazine_item_id) \
		and not _tyreg_magazine_charge_ids(_tyreg_magazine_item_id).is_empty()


func _on_tyreg_interacted() -> void:
	var actor_id := str(_tyreg_interactable.active_character) \
		if is_instance_valid(_tyreg_interactable) else ""
	# Re-evaluate after GameState's trigger signal: another synchronous authority listener may have
	# moved/downed a body or transferred the exact magazine since the preflight.
	if not _tyreg_acceptance_truth(actor_id, true):
		_sync_tyreg_interaction_presenter()
		return
	_tyreg_phase = TYREG_PHASE_JOINING
	_tyreg_join_actor = actor_id
	_sync_tyreg_interaction_presenter()
	_publish_chase_authority()
	_tyreg_phase = TYREG_PHASE_ACCEPTED
	_sync_tyreg_interaction_presenter()
	_set_preview_step("lockout_tyreg_accepted")
	_show_note("Tyreg falls in. Three physical rounds — she makes each one count.", 2.4)
	_publish_chase_authority()
	_arm_suppress()


## Tyreg is now a real escort: her GameState body trails the pair, and a shot requires that same
## conscious body, authoritative LOS to the target, and one exact charge in her held magazine.
func _arm_suppress() -> void:
	var sched = _get_scheduler()
	if sched == null or not _tyreg_help_accepted():
		return
	var gs = _get_game_state()
	if gs != null and _tyreg_can_act(gs):
		_update_tyreg_escort_follow(gs)
		var best = null
		var best_d := INF
		var tyreg_pos: Vector3 = gs.get_position(TYREG_ID)
		for enemy in _enemies:
			if not is_instance_valid(enemy) or not enemy.is_alive() or enemy.is_stunned():
				continue
			var p: Vector3 = gs.get_position(enemy.char_id)
			if _planar_distance(tyreg_pos, p) > TYREG_SUPPRESS_RANGE \
					or not gs.grid.has_line_of_sight(tyreg_pos, p):
				continue
			for cid in ["aster", "peris"]:
				if not gs.characters.has(cid) or gs.is_downed(cid) \
						or not gs.is_narratively_available(cid):
					continue
				var cp: Vector3 = gs.get_position(cid)
				var d := _planar_distance(p, cp)
				if d < 6.0 and d < best_d:
					best_d = d
					best = enemy
		if best != null:
			_consume_tyreg_round_for_target(best)
	var charges_left := _tyreg_suppress_charge_count()
	if charges_left > 0 and _tyreg_help_accepted():
		_arm_chase_recurring("chase_suppress", 1.2, _arm_suppress, 1.2)
	else:
		_stop_chase_recurring("chase_suppress")
	_publish_chase_authority()


func _consume_tyreg_round_for_target(enemy) -> bool:
	var gs = _get_game_state()
	if gs == null or enemy == null or not _tyreg_can_act(gs):
		return false
	var source_id := _tyreg_magazine_item_id
	var charge_ids := _tyreg_magazine_charge_ids(source_id)
	if charge_ids.is_empty():
		return false
	var charge_id := str(charge_ids[0])
	var remaining: Array[String] = []
	for index in range(1, charge_ids.size()):
		remaining.append(str(charge_ids[index]))
	_suppress_transaction = {
		"phase": SUPPRESS_TX_RESERVING,
		"source_item_id": source_id,
		"replacement_item_id": "",
		"charge_id": charge_id,
		"remaining_charge_ids": remaining.duplicate(),
		"target_id": str(enemy.char_id),
		"stun_deadline": _get_scheduler_tick() + SUPPRESS_SECS,
	}
	# Reserve the exact source, round token, target, and deadline before the source leaves GameState.
	_publish_chase_authority()
	_remove_item(source_id)
	var replacement_id := _spawn_item(
		TYREG_MAGAZINE_TYPE,
		gs.get_position(TYREG_ID),
		_tyreg_magazine_properties(remaining)
	)
	if replacement_id == "":
		return false
	_suppress_transaction["replacement_item_id"] = replacement_id
	_publish_chase_authority()
	if not _pick_up_item(TYREG_ID, replacement_id):
		return false
	_apply_reserved_suppress_effect()
	_tyreg_magazine_item_id = replacement_id
	_clear_suppress_transaction()
	var charges_left := _tyreg_suppress_charge_count()
	_show_note("Suppressed. %d rounds left." % charges_left, 1.4)
	_publish_chase_authority()
	return true


func _apply_reserved_suppress_effect() -> void:
	var target_id := str(_suppress_transaction.get("target_id", ""))
	var target = _enemy_by_id(target_id)
	if target == null or not is_instance_valid(target) or not target.is_alive():
		return
	var remaining := maxf(
		0.0,
		float(_suppress_transaction.get("stun_deadline", _get_scheduler_tick()))
			- _get_scheduler_tick()
	)
	if remaining > 0.0:
		target.stun(remaining)


func _update_tyreg_escort_follow(gs) -> void:
	if gs.is_moving(TYREG_ID):
		return
	var anchors: Array[Vector3] = []
	for char_id in ["aster", "peris"]:
		if gs.characters.has(char_id) and gs.is_narratively_available(char_id) \
				and not gs.is_downed(char_id):
			anchors.append(gs.get_position(char_id))
	if anchors.is_empty():
		return
	var target := Vector3.ZERO
	for anchor in anchors:
		target += anchor
	target /= float(anchors.size())
	target.x -= 1.6
	var tyreg_pos: Vector3 = gs.get_position(TYREG_ID)
	if _planar_distance(tyreg_pos, target) > TYREG_ESCORT_FOLLOW_DISTANCE:
		gs.command_move_to_pos(TYREG_ID, target)


func _tyreg_can_act(gs) -> bool:
	return gs != null and gs.grid != null and gs.characters.has(TYREG_ID) \
		and gs.is_narratively_available(TYREG_ID) and not gs.is_downed(TYREG_ID) \
		and not gs.is_knocked_down(TYREG_ID) \
		and str(_suppress_transaction.get("phase", SUPPRESS_TX_IDLE)) == SUPPRESS_TX_IDLE \
		and _tyreg_owns_exact_magazine(_tyreg_magazine_item_id) \
		and not _tyreg_magazine_charge_ids(_tyreg_magazine_item_id).is_empty()


func _tyreg_body_at_authored_station(gs) -> bool:
	return gs != null and gs.characters.has(TYREG_ID) \
		and _planar_distance(gs.get_position(TYREG_ID), TYREG_STATION) \
			<= TYREG_STATION_TOLERANCE \
		and absf(gs.get_position(TYREG_ID).y - TYREG_STATION.y) <= 1.25


func _tyreg_owns_exact_magazine(item_id: String) -> bool:
	var gs = _get_game_state()
	if gs == null or item_id == "" or not gs.items.has(item_id) \
			or not gs.characters.has(TYREG_ID):
		return false
	var item: Dictionary = gs.items[item_id]
	return _is_tyreg_magazine(item_id) and str(item.get("holder", "")) == TYREG_ID \
		and str(item.get("location", "")) == "hand" \
		and item_id in gs.get_hand_items(TYREG_ID)


func _is_tyreg_magazine(item_id: String) -> bool:
	var gs = _get_game_state()
	if gs == null or item_id == "" or not gs.items.has(item_id):
		return false
	var item: Dictionary = gs.items[item_id]
	var properties: Dictionary = item.get("properties", {})
	return str(item.get("type", "")) == TYREG_MAGAZINE_TYPE \
		and str(properties.get("authored_source", "")) == TYREG_MAGAZINE_SOURCE


func _tyreg_magazine_charge_ids(item_id: String) -> Array[String]:
	var result: Array[String] = []
	var gs = _get_game_state()
	if not _is_tyreg_magazine(item_id) or gs == null:
		return result
	var item: Dictionary = gs.items[item_id]
	var properties: Dictionary = item.get("properties", {})
	for charge_id_v in properties.get("charge_ids", []) as Array:
		var charge_id := str(charge_id_v)
		if charge_id != "" and not result.has(charge_id):
			result.append(charge_id)
	return result


func _tyreg_suppress_charge_count() -> int:
	if _tyreg_owns_exact_magazine(_tyreg_magazine_item_id):
		return _tyreg_magazine_charge_ids(_tyreg_magazine_item_id).size()
	if str(_suppress_transaction.get("phase", "")) == SUPPRESS_TX_RESERVING:
		var replacement_id := str(_suppress_transaction.get("replacement_item_id", ""))
		if _tyreg_owns_exact_magazine(replacement_id):
			return _tyreg_magazine_charge_ids(replacement_id).size()
	return 0


func _initial_tyreg_charge_ids() -> Array[String]:
	var result: Array[String] = []
	for ordinal in range(1, SUPPRESS_CHARGES + 1):
		result.append("tyreg_suppress_round_%d" % ordinal)
	return result


func _tyreg_magazine_properties(charge_ids: Array[String]) -> Dictionary:
	return {
		"authored_source": TYREG_MAGAZINE_SOURCE,
		"display_name": "Tyreg's Suppress magazine",
		"charge_ids": charge_ids.duplicate(),
		"hand_slots": 1,
		"endocytosis_allowed": false,
	}


func _clear_suppress_transaction() -> void:
	_suppress_transaction = {
		"phase": SUPPRESS_TX_IDLE,
		"source_item_id": "",
		"replacement_item_id": "",
		"charge_id": "",
		"remaining_charge_ids": [],
		"target_id": "",
		"stun_deadline": -1.0,
	}


func _restore_suppress_transaction(raw: Variant) -> void:
	_clear_suppress_transaction()
	if not raw is Dictionary or str(raw.get("phase", SUPPRESS_TX_IDLE)) != SUPPRESS_TX_RESERVING:
		return
	var remaining: Array[String] = []
	for charge_id_v in raw.get("remaining_charge_ids", []) as Array:
		var charge_id := str(charge_id_v)
		if charge_id != "" and not remaining.has(charge_id):
			remaining.append(charge_id)
	var deadline := float(raw.get("stun_deadline", -1.0))
	if not is_finite(deadline):
		deadline = -1.0
	_suppress_transaction = {
		"phase": SUPPRESS_TX_RESERVING,
		"source_item_id": str(raw.get("source_item_id", "")),
		"replacement_item_id": str(raw.get("replacement_item_id", "")),
		"charge_id": str(raw.get("charge_id", "")),
		"remaining_charge_ids": remaining,
		"target_id": str(raw.get("target_id", "")),
		"stun_deadline": deadline,
	}


func _tyreg_help_accepted() -> bool:
	return _tyreg_phase == TYREG_PHASE_ACCEPTED


func _planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _sync_tyreg_presenter() -> void:
	if not is_instance_valid(_tyreg_presenter):
		return
	var gs = _get_game_state()
	var body_exists: bool = gs != null and gs.characters.has(TYREG_ID)
	_tyreg_presenter.visible = body_exists
	_tyreg_presenter.collision_layer = 2 if body_exists else 0
	_tyreg_presenter.collision_mask = 2 if body_exists else 0
	if not body_exists:
		return
	_tyreg_presenter.set("game_state", gs)
	_tyreg_presenter.set("grid_world", gs.grid)
	_tyreg_presenter.global_position = gs.get_render_position(TYREG_ID)
	_tyreg_presenter.rotation.z = PI * 0.5 if gs.is_downed(TYREG_ID) else 0.0


func _sync_tyreg_interaction_presenter() -> void:
	if not is_instance_valid(_tyreg_interactable):
		return
	var gs = _get_game_state()
	var enabled: bool = _tyreg_phase == TYREG_PHASE_AVAILABLE \
		and gs != null and gs.characters.has(TYREG_ID) \
		and _tyreg_body_at_authored_station(gs) \
		and gs.is_narratively_available(TYREG_ID) and not gs.is_downed(TYREG_ID) \
		and not gs.is_knocked_down(TYREG_ID) \
		and _tyreg_owns_exact_magazine(_tyreg_magazine_item_id) \
		and not _tyreg_magazine_charge_ids(_tyreg_magazine_item_id).is_empty()
	if _tyreg_interactable.has_method("restore_one_shot_presenter"):
		_tyreg_interactable.call("restore_one_shot_presenter", false, enabled)
	else:
		_tyreg_interactable.set_interaction_enabled(enabled)


func _tyreg_magazine_at_ground(item_id: String, expected_position: Vector3) -> bool:
	var gs = _get_game_state()
	if not _is_tyreg_magazine(item_id) or gs == null:
		return false
	var item: Dictionary = gs.items[item_id]
	return str(item.get("holder", "")) == "" and str(item.get("location", "")) == "ground" \
		and (item.get("position", Vector3.INF) as Vector3).distance_to(expected_position) <= 0.05


func _charge_ids_equal(actual: Array[String], expected_raw: Variant) -> bool:
	var expected: Array[String] = []
	if expected_raw is Array:
		for charge_id_v in expected_raw:
			expected.append(str(charge_id_v))
	return actual == expected


## Restore reconciliation never searches for a similar magazine and never rebuilds a missing body or
## charge. A reservation before source removal rolls back. Once the exact replacement exists, only
## that identity may complete the shot; wrong-holder/missing/corrupt truth remains blocked.
func _reconcile_restored_tyreg_authority(allow_suppress_effect_commit: bool) -> bool:
	var changed := false
	var gs = _get_game_state()
	if gs == null:
		return false
	match _tyreg_phase:
		TYREG_PHASE_SEEDING:
			if _tyreg_owns_exact_magazine(_tyreg_magazine_item_id):
				_tyreg_phase = TYREG_PHASE_AVAILABLE
				changed = true
			elif _tyreg_body_at_authored_station(gs) \
					and _tyreg_magazine_at_ground(_tyreg_magazine_item_id, TYREG_STATION) \
					and _pick_up_item(TYREG_ID, _tyreg_magazine_item_id):
				_tyreg_phase = TYREG_PHASE_AVAILABLE
				changed = true
			else:
				_tyreg_phase = TYREG_PHASE_UNAVAILABLE
				changed = true
		TYREG_PHASE_JOINING:
			# No irreversible mutation lies between JOINING and ACCEPTED, so a save on the first
			# publication retracts to the still-physical offer and lets the player retry.
			_tyreg_phase = TYREG_PHASE_AVAILABLE \
				if _tyreg_body_at_authored_station(gs) \
				and _tyreg_owns_exact_magazine(_tyreg_magazine_item_id) \
				and not _tyreg_magazine_charge_ids(_tyreg_magazine_item_id).is_empty() \
				else TYREG_PHASE_UNAVAILABLE
			changed = true
		TYREG_PHASE_AVAILABLE:
			if not _tyreg_body_at_authored_station(gs) \
					or not _tyreg_owns_exact_magazine(_tyreg_magazine_item_id):
				_tyreg_phase = TYREG_PHASE_UNAVAILABLE
				changed = true

	if str(_suppress_transaction.get("phase", SUPPRESS_TX_IDLE)) != SUPPRESS_TX_RESERVING:
		_sync_tyreg_presenter()
		_sync_tyreg_interaction_presenter()
		return changed
	var source_id := str(_suppress_transaction.get("source_item_id", ""))
	var replacement_id := str(_suppress_transaction.get("replacement_item_id", ""))
	var source_exists: bool = source_id != "" and gs.items.has(source_id)
	var replacement_exists: bool = replacement_id != "" and gs.items.has(replacement_id)
	if source_exists:
		if _tyreg_owns_exact_magazine(source_id) and not replacement_exists:
			# Save landed on the reservation publication before remove_item: nothing fired.
			_tyreg_magazine_item_id = source_id
			_clear_suppress_transaction()
			changed = true
			_sync_tyreg_presenter()
			_sync_tyreg_interaction_presenter()
			return changed
		# Duplicate, displaced, or wrong-holder source truth is ambiguous. Never choose a side.
		_sync_tyreg_presenter()
		_sync_tyreg_interaction_presenter()
		return changed
	if not replacement_exists or not _is_tyreg_magazine(replacement_id) \
			or not _charge_ids_equal(
				_tyreg_magazine_charge_ids(replacement_id),
				_suppress_transaction.get("remaining_charge_ids", [])
			):
		_sync_tyreg_presenter()
		_sync_tyreg_interaction_presenter()
		return changed
	if not _tyreg_owns_exact_magazine(replacement_id):
		if not _tyreg_magazine_at_ground(replacement_id, gs.get_position(TYREG_ID)) \
				or not _pick_up_item(TYREG_ID, replacement_id):
			_sync_tyreg_presenter()
			_sync_tyreg_interaction_presenter()
			return changed
		changed = true
	if not allow_suppress_effect_commit:
		_sync_tyreg_presenter()
		_sync_tyreg_interaction_presenter()
		return changed
	_apply_reserved_suppress_effect()
	_tyreg_magazine_item_id = replacement_id
	_clear_suppress_transaction()
	changed = true
	_sync_tyreg_presenter()
	_sync_tyreg_interaction_presenter()
	return changed


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
		_arm_chase_recurring("chase_close_call", 1.0, _close_call_watch, 1.0)
	_publish_chase_authority()

## F2: a wipe resets THE CHASE, not just the party — waves despawn, the timeline re-arms, and the
## scanner waits again. Respawning four steps from live pursuers was the probe's alt-F4 moment.
func _restart_fragment() -> void:
	if _chase_started and _checkpoint_x > 0.0:
		_checkpoint_resume()
		return
	var sched = _get_scheduler()
	if sched != null:
		for tag in ["chase_wave_1", "chase_wave_2", "chase_decline_watch", "chase_close_call",
				"chase_pursuit", "chase_portal_follow", "chase_door_hold", "chase_suppress", "chase_directive",
				"chase_hazards", DOOR_PHASE_TAG, GANTRY_PHASE_TAG]:
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
	_recurring_epochs.clear()
	_one_shot_deadlines.clear()
	_one_shot_payloads.clear()
	_clear_seal_transaction()
	_gantry_phase = GANTRY_PHASE_STANDING
	_gantry_phase_start = -1.0
	_gantry_phase_deadline = -1.0
	_set_trench_blocked(true)
	_sync_gantry_presenter()
	_reset_service_door_for_full_restart()
	for wch in _channels:
		if is_instance_valid(wch) and wch.has_method("clear_sweep_refractory"):
			wch.clear_sweep_refractory()
	_trip_refractory.clear()
	_fallen.clear()
	_wave_count = 0
	# from the top means FROM THE TOP: the boundary scanner re-arms so tags can be presented
	# again (a spent one-shot left the whole run unstartable after a full wipe)
	if is_instance_valid(_boundary_scanner) and _boundary_scanner.has_method("reset"):
		_boundary_scanner.call("reset")
	super._restart_fragment()
	_restore_pair_after_reset(fragment.spawns if fragment != null else {})
	_publish_chase_authority()
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

func _build_barricade() -> void:
	var mid := (BARRICADE_X0 + BARRICADE_X1) * 0.5
	for i in range(9):
		var rz := -CORRIDOR_HALF_Z + (float(i) + 0.5) * (CORRIDOR_HALF_Z * 2.0 / 9.0)
		_add_box(self, Vector3(mid + (0.5 if i % 2 == 0 else -0.4), 0.5 + 0.35 * float(i % 3), rz),
			Vector3(1.4, 0.5 + 0.3 * float(i % 3), 0.7), Color(0.16, 0.15, 0.17))
	_add_label(self, "SHELF COLLAPSE", Vector3(mid, 3.0, 3.4), Color(0.62, 0.58, 0.55))
	_clamber = CrawlTunnel.new()
	_clamber.name = "ClamberBarricade"
	_clamber.data_id = "lockout_clamber_barricade"
	_clamber.description = "Clamber over the collapsed shelf"
	_clamber.tutorial_label = "BOOST / PULL"
	_clamber.configure(_get_game_state(), Vector3(BARRICADE_X0 - 1.2, 0, 0),
		[Vector3(mid, 1.3, 0.0), Vector3(BARRICADE_X1 + 1.4, 0, 0)], 1.4, 2.2)
	_clamber.conceal_riders = false
	# One character crosses per commitment. The partner remains the physical booster below; on the
	# second interaction the first character is now the puller above. Sending an arbitrary selected
	# group through together erased both roles and let the requirement collapse into a party flag.
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
	for pin_index in range(PINCHES.size()):
		var pin: Array = PINCHES[pin_index]
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
			if not is_instance_valid(enemy2) or not enemy2.is_alive() or enemy2.is_stunned() \
					or gs.is_external_traversal_active(enemy2.char_id):
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
				# The pack behind enters a locked two-stage clamber over the prone body. The
				# time toll remains per body, but it now has an authoritative midpoint and
				# destination instead of pretending that standing stunned is a climb.
				_begin_pinch_clamber(gs, enemy2, pin_index, pile, ep)


func _begin_pinch_clamber(gs, enemy, pin_index: int, pile: int, origin: Vector3) -> bool:
	if pin_index < 0 or pin_index >= PINCHES.size() or pile <= 0:
		return false
	var pin: Array = PINCHES[pin_index]
	var px := float(pin[0])
	var gz := float(pin[1])
	var duration := minf(CLIMB_SECS * float(pile), 4.5)
	var apex := Vector3(px, CLAMBER_APEX_Y + minf(0.45, float(pile - 1) * 0.12), gz)
	return _command_lockout_traversal(gs, str(enemy.char_id),
		_pinch_up_traversal_id(str(enemy.char_id), pin_index, pile), apex, duration * 0.5, origin)


func _begin_barricade_clamber(gs, enemy, origin: Vector3) -> bool:
	var apex := Vector3((BARRICADE_X0 + BARRICADE_X1) * 0.5, CLAMBER_APEX_Y, 0.0)
	return _command_lockout_traversal(gs, str(enemy.char_id),
		_barricade_up_traversal_id(str(enemy.char_id)), apex,
		BARRICADE_ENEMY_CLAMBER_SECS * 0.5, origin)


func _command_lockout_traversal(
		gs, char_id: String, traversal_id: StringName, data_destination: Vector3,
		duration: float, expected_origin: Vector3 = Vector3.INF) -> bool:
	if gs == null or not gs.characters.has(char_id) or gs.is_external_traversal_active(char_id):
		return false
	var data_origin: Vector3 = gs.get_position(char_id)
	if expected_origin != Vector3.INF and data_origin.distance_to(expected_origin) > 0.75:
		return false
	var render_destination := data_destination
	if gs.coord_map != null and gs.coord_map.has_method("to_world"):
		render_destination = gs.coord_map.to_world(data_destination)
	return bool(gs.command_external_traversal(
		char_id, traversal_id, data_destination, gs.get_render_position(char_id),
		render_destination, duration, &"locked"))


func _barricade_up_traversal_id(char_id: String) -> StringName:
	return StringName("lockout_barricade_up:%s" % char_id)


func _barricade_down_traversal_id(char_id: String) -> StringName:
	return StringName("lockout_barricade_down:%s" % char_id)


func _pinch_up_traversal_id(char_id: String, pin_index: int, pile: int) -> StringName:
	return StringName("lockout_pinch_up:%d:%d:%s" % [pin_index, pile, char_id])


func _pinch_down_traversal_id(char_id: String, pin_index: int) -> StringName:
	return StringName("lockout_pinch_down:%d:%s" % [pin_index, char_id])


func _wire_lockout_external_traversal_signals() -> void:
	var gs = _get_game_state()
	if _traversal_signal_game_state != null and _traversal_signal_game_state != gs \
			and is_instance_valid(_traversal_signal_game_state) \
			and _traversal_signal_game_state.external_traversal_finished.is_connected(
				_on_lockout_external_traversal_finished):
		_traversal_signal_game_state.external_traversal_finished.disconnect(
			_on_lockout_external_traversal_finished)
	_traversal_signal_game_state = gs
	if gs != null and not gs.external_traversal_finished.is_connected(
			_on_lockout_external_traversal_finished):
		gs.external_traversal_finished.connect(_on_lockout_external_traversal_finished)


func _on_lockout_external_traversal_finished(
		char_id: String, traversal_id: StringName) -> void:
	var gs = _get_game_state()
	if gs == null or not gs.characters.has(char_id):
		return
	if traversal_id == _barricade_up_traversal_id(char_id):
		_command_lockout_traversal(gs, char_id, _barricade_down_traversal_id(char_id),
			Vector3(BARRICADE_X1 + 1.6, 0.0, 0.0),
			BARRICADE_ENEMY_CLAMBER_SECS * 0.5)
		return
	var parts := str(traversal_id).split(":")
	if parts.size() != 4 or parts[0] != "lockout_pinch_up" or parts[3] != char_id:
		return
	var pin_index := int(parts[1])
	var pile := maxi(1, int(parts[2]))
	if pin_index < 0 or pin_index >= PINCHES.size():
		return
	var pin: Array = PINCHES[pin_index]
	var duration := minf(CLIMB_SECS * float(pile), 4.5)
	_command_lockout_traversal(gs, char_id, _pinch_down_traversal_id(char_id, pin_index),
		Vector3(float(pin[0]) + PINCH_CLAMBER_EXIT_X, 0.0, float(pin[1])), duration * 0.5)

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
			_publish_chase_authority()
			return
		# barricade funnel: a pursuer at the wall whose quarry is beyond enters the same terrain
		# as a locked rise-and-descent traversal rather than waiting beside an endpoint teleport.
		for enemy in _enemies:
			if not is_instance_valid(enemy) or not enemy.is_alive() or enemy.is_stunned() \
					or gs.is_external_traversal_active(enemy.char_id):
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
			_begin_barricade_clamber(gs, enemy, ep)
	if sched != null:
		_arm_chase_recurring("chase_hazards", 0.5, _hazard_poll, 0.5)
	_publish_chase_authority()

## THE PAIR GATE: one conscious partner must be physically at the bottom to boost, or at the top
## to pull. Each interaction moves only the active climber, preserving the two distinct roles.
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
	var actor := str(_clamber.active_character) if is_instance_valid(_clamber) else ""
	if actor not in ["aster", "peris"]:
		return false
	var partner := "peris" if actor == "aster" else "aster"
	for cid in [actor, partner]:
		if not _pair_member_present(gs, cid) or gs.is_downed(cid):
			return false
		if gs.is_external_traversal_active(cid):
			return false
	var mouth := Vector3(BARRICADE_X0 - 1.2, 0.0, 0.0)
	var actor_pos: Vector3 = gs.get_position(actor)
	if Vector2(actor_pos.x - mouth.x, actor_pos.z - mouth.z).length() > PAIR_NEAR_X:
		return false
	var partner_pos: Vector3 = gs.get_position(partner)
	var boosts_below := Vector2(partner_pos.x - mouth.x, partner_pos.z - mouth.z).length() <= PAIR_NEAR_X
	var pulls_above := partner_pos.x >= BARRICADE_X1 \
		and partner_pos.x <= BARRICADE_X1 + PAIR_NEAR_X \
		and absf(partner_pos.z) <= PAIR_NEAR_X
	return boosts_below or pulls_above

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
		_publish_chase_authority()

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
	_wipe_count += 1
	_fall_pos = gs.get_position(fallen_id)
	var sched = _get_scheduler()
	if sched == null:
		_restart_fragment()
		return
	_restart_deadline = float(sched.get_current_tick()) + 1.5
	_schedule_fragment_restart_at(_restart_deadline)
	_publish_fragment_authority()
	_publish_chase_authority()

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
	var preserved_door_deadline := float(_one_shot_deadlines.get(DOOR_PHASE_TAG, -1.0))
	var preserved_door_payload: Dictionary = (_one_shot_payloads.get(DOOR_PHASE_TAG, {}) as Dictionary).duplicate(true)
	var preserved_gantry_deadline := float(_one_shot_deadlines.get(GANTRY_PHASE_TAG, -1.0))
	var preserved_gantry_payload: Dictionary = (_one_shot_payloads.get(GANTRY_PHASE_TAG, {}) as Dictionary).duplicate(true)
	if sched != null:
		for tag in ["chase_wave_1", "chase_wave_2", "chase_decline_watch", "chase_close_call",
				"chase_pursuit", "chase_portal_follow", "chase_door_hold", "chase_suppress",
				"chase_directive", "chase_hazards", DOOR_PHASE_TAG, GANTRY_PHASE_TAG]:
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
	_recurring_epochs.clear()
	_one_shot_deadlines.clear()
	_one_shot_payloads.clear()
	if preserved_door_deadline >= 0.0 and not preserved_door_payload.is_empty():
		_one_shot_deadlines[DOOR_PHASE_TAG] = preserved_door_deadline
		_one_shot_payloads[DOOR_PHASE_TAG] = preserved_door_payload
		_schedule_chase_one_shot_at(DOOR_PHASE_TAG, preserved_door_deadline)
	elif _door_phase == DOOR_PHASE_SEALED:
		_arm_door_hold()
	if preserved_gantry_deadline >= 0.0 and not preserved_gantry_payload.is_empty():
		_one_shot_deadlines[GANTRY_PHASE_TAG] = preserved_gantry_deadline
		_one_shot_payloads[GANTRY_PHASE_TAG] = preserved_gantry_payload
		_schedule_chase_one_shot_at(GANTRY_PHASE_TAG, preserved_gantry_deadline)
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
		_schedule_chase_one_shot_after("chase_wave_2", 5.5, "wave", {
			"count": 2, "near_party": false,
			"base_x_override": maxf(_checkpoint_x - 18.0, 2.0),
		})
		_arm_chase_recurring("chase_close_call", 1.0, _close_call_watch, 1.5)
		_arm_chase_recurring("chase_hazards", 0.5, _hazard_poll, 1.0)
		if not _decline_wave_fired:
			_arm_chase_recurring("chase_decline_watch", 1.0, _decline_watch, 1.0)
	_arm_portal_follow()
	_publish_chase_authority()
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
func _on_exit_shelter_rested(it: Node = null) -> bool:
	if not _chase_started:
		_show_note("Endo looks up, nods at the checkpoint. Nothing out here for you yet.", 2.6)
		_retract_exit_shelter_source_receipt(it)
		return false
	# THE END GATE NEEDS THE PAIR: both Aster and Peris, up and inside the maintained section, or
	# nobody rests. (Endo never speaks; the refusal is a gesture.)
	var gs = _get_game_state()
	if gs != null:
		for cid in ["aster", "peris"]:
			if not _pair_member_present(gs, cid) or gs.is_downed(cid) \
					or gs.get_position(cid).x < WALL_X - 16.0:
				_show_note("Endo holds up two fingers, then points back down the corridor.", 2.8)
				_retract_exit_shelter_source_receipt(it)
				return false
	var completed := super._on_exit_shelter_rested(it)
	if _phase == "complete":
		_cancel_chase_scheduler_tags()
		_recurring_epochs.clear()
		_one_shot_deadlines.clear()
		_one_shot_payloads.clear()
	_publish_chase_authority()
	return completed


## Lockout's pursuit director is a gameplay state machine, not scene choreography. The stable
## world-state record carries one-shot wave deadlines, fixed recurring epochs, progression, and
## crowd-governor state so a save cannot delete pressure, repeat a wave, or regenerate a lever.
func _chase_authority_state() -> Dictionary:
	var pursuer_ids: Array = []
	for enemy in _enemies:
		if is_instance_valid(enemy) and str(enemy.char_id) != "":
			pursuer_ids.append(str(enemy.char_id))
	pursuer_ids.sort()
	return {
		"version": CHASE_AUTHORITY_VERSION,
		"phase": _phase,
		"chase_started": _chase_started,
		"pursuit_armed": _pursuit_armed,
		"defer_pursuit_start": _defer_pursuit_start,
		"scanner_trigger_consumed": _scanner_trigger_consumed,
		"door_phase": _door_phase,
		"door_phase_start": _door_phase_start,
		"door_phase_deadline": _door_phase_deadline,
		"door_breacher": _door_breacher,
		"door_trigger_consumed": _door_trigger_consumed,
		"seal_trigger_consumed": _portable_chase_int_map(_seal_trigger_consumed),
		"seal_transaction": _seal_transaction.duplicate(true),
		"tyreg_phase": _tyreg_phase,
		"tyreg_join_actor": _tyreg_join_actor,
		"tyreg_magazine_item_id": _tyreg_magazine_item_id,
		"suppress_transaction": _suppress_transaction.duplicate(true),
		"decline_wave_fired": _decline_wave_fired,
		"wave_count": _wave_count,
		"last_close_call": _last_close_call,
		"checkpoint_x": _checkpoint_x,
		"gantry_phase": _gantry_phase,
		"gantry_phase_start": _gantry_phase_start,
		"gantry_phase_deadline": _gantry_phase_deadline,
		"trip_refractory": _portable_chase_float_map(_trip_refractory),
		"fallen": _fallen.keys(),
		"recurring_epochs": _portable_chase_float_map(_recurring_epochs),
		"one_shot_deadlines": _portable_chase_float_map(_one_shot_deadlines),
		"one_shot_payloads": _one_shot_payloads.duplicate(true),
		"pursuer_ids": pursuer_ids,
	}


func _publish_chase_authority() -> void:
	if _restoring_chase_authority:
		return
	var gs = _get_game_state()
	if gs != null and gs.has_method("set_world_state"):
		gs.set_world_state(CHASE_AUTHORITY_KEY, _chase_authority_state())


func on_game_state_snapshot_restored() -> void:
	super.on_game_state_snapshot_restored()
	# A presenter can survive while GameState/grid authority is replaced. Never
	# reuse a future timeline's derived pursuit field after that boundary.
	_invalidate_flow_field_cache()
	_cancel_chase_scheduler_tags()
	var gs = _get_game_state()
	var raw: Variant = gs.get_world_state(CHASE_AUTHORITY_KEY, null) \
			if gs != null and gs.has_method("get_world_state") else null
	if not raw is Dictionary or int(raw.get("version", 0)) not in [2, 3, 4, CHASE_AUTHORITY_VERSION]:
		_retract_chase_presenter_to_defaults()
		_reconcile_restored_lockout_controls()
		_reconcile_restored_seal_sources()
		return
	var saved: Dictionary = raw
	var saved_version := int(saved.get("version", 0))
	_restoring_chase_authority = true
	_phase = str(saved.get("phase", "ready"))
	_chase_started = bool(saved.get("chase_started", false))
	_pursuit_armed = bool(saved.get("pursuit_armed", false))
	_defer_pursuit_start = bool(saved.get("defer_pursuit_start", _defer_pursuit_start))
	if saved_version >= CHASE_AUTHORITY_VERSION:
		_scanner_trigger_consumed = maxi(0, int(saved.get("scanner_trigger_consumed", 0)))
		_door_trigger_consumed = maxi(0, int(saved.get("door_trigger_consumed", 0)))
		_seal_trigger_consumed = _validated_chase_int_map(
			saved.get("seal_trigger_consumed", {}))
		_restore_seal_transaction(saved.get("seal_transaction", {}))
	else:
		# v2-v4 knew the committed outcome but not its source receipt. Adopt only a receipt already
		# present in the restored Interactable registry; never manufacture an interaction from flags.
		_scanner_trigger_consumed = maxi(0,
			_lockout_source_trigger_count(_boundary_scanner) if _chase_started else 0)
		_door_trigger_consumed = 0
		_seal_trigger_consumed.clear()
		_clear_seal_transaction()
	_door_phase = str(saved.get("door_phase", DOOR_PHASE_OPEN))
	if _door_phase not in [DOOR_PHASE_OPEN, DOOR_PHASE_CLOSING, DOOR_PHASE_SEALED,
			DOOR_PHASE_BREACHING, DOOR_PHASE_OPENING, DOOR_PHASE_BREACHED]:
		_door_phase = DOOR_PHASE_OPEN
	_door_phase_start = float(saved.get("door_phase_start", -1.0))
	_door_phase_deadline = float(saved.get("door_phase_deadline", -1.0))
	_door_breacher = str(saved.get("door_breacher", ""))
	if saved_version < CHASE_AUTHORITY_VERSION and _door_phase != DOOR_PHASE_OPEN:
		_door_trigger_consumed = maxi(0, _lockout_source_trigger_count(_service_door))
	if saved_version >= 4:
		_tyreg_phase = str(saved.get("tyreg_phase", TYREG_PHASE_UNAVAILABLE))
		if _tyreg_phase not in TYREG_PHASES:
			_tyreg_phase = TYREG_PHASE_UNAVAILABLE
		_tyreg_join_actor = str(saved.get("tyreg_join_actor", ""))
		_tyreg_magazine_item_id = str(saved.get("tyreg_magazine_item_id", ""))
		_restore_suppress_transaction(saved.get("suppress_transaction", {}))
	else:
		# Legacy flags/counters named an outcome with no canonical body or inventory. Do not mint
		# either from those proxies; only v4 physical truth can make Tyreg available.
		_tyreg_phase = TYREG_PHASE_UNAVAILABLE
		_tyreg_join_actor = ""
		_tyreg_magazine_item_id = ""
		_clear_suppress_transaction()
	_decline_wave_fired = bool(saved.get("decline_wave_fired", false))
	_wave_count = maxi(0, int(saved.get("wave_count", 0)))
	_last_close_call = float(saved.get("last_close_call", -100.0))
	_checkpoint_x = float(saved.get("checkpoint_x", -1.0))
	_gantry_phase = str(saved.get("gantry_phase", GANTRY_PHASE_STANDING))
	if _gantry_phase not in [GANTRY_PHASE_STANDING, GANTRY_PHASE_FALLING, GANTRY_PHASE_BRIDGED]:
		_gantry_phase = GANTRY_PHASE_STANDING
	_gantry_phase_start = float(saved.get("gantry_phase_start", -1.0))
	_gantry_phase_deadline = float(saved.get("gantry_phase_deadline", -1.0))
	_trip_refractory = _validated_chase_float_map(saved.get("trip_refractory", {}))
	_fallen.clear()
	for id_v in (saved.get("fallen", []) as Array):
		_fallen[str(id_v)] = true
	_recurring_epochs = _validated_chase_float_map(saved.get("recurring_epochs", {}))
	_one_shot_deadlines = _validated_chase_float_map(saved.get("one_shot_deadlines", {}))
	_one_shot_payloads = (saved.get("one_shot_payloads", {}) as Dictionary).duplicate(true)
	_restore_pursuer_presenters(saved.get("pursuer_ids", []) as Array)
	_apply_restored_chase_presenters()
	var normalized_tyreg := _reconcile_restored_tyreg_authority(false)
	_restoring_chase_authority = false
	var normalized_controls := _reconcile_restored_lockout_controls()
	var normalized_seal := _reconcile_restored_seal_sources()
	if str(_seal_transaction.get("phase", SEAL_TX_IDLE)) != SEAL_TX_IDLE:
		normalized_seal = _finish_seal_transaction() or normalized_seal
	if normalized_tyreg or normalized_controls or normalized_seal:
		_publish_chase_authority()
	_rearm_chase_callbacks()


func _restore_seal_transaction(raw: Variant) -> void:
	_clear_seal_transaction()
	if not raw is Dictionary:
		return
	var phase := str(raw.get("phase", SEAL_TX_IDLE))
	if phase not in [SEAL_TX_RESERVED, SEAL_TX_ITEM_REMOVED]:
		return
	var deadline := float(raw.get("stun_deadline", -1.0))
	if not is_finite(deadline):
		deadline = -1.0
	_seal_transaction = {
		"phase": phase,
		"source_id": str(raw.get("source_id", "")),
		"source_trigger_count": maxi(0, int(raw.get("source_trigger_count", 0))),
		"actor": str(raw.get("actor", "")),
		"item_id": str(raw.get("item_id", "")),
		"pad_name": str(raw.get("pad_name", "")),
		"stun_deadline": deadline,
	}


## Close the save seam between GameState accepting a one-shot source and the synchronous chunk
## callback publishing its consequence. A valid accepted receipt finishes the exact action; a
## malformed/stale receipt is consumed and re-armed without granting the outcome.
func _reconcile_restored_lockout_controls() -> bool:
	var changed := false
	for action_id in ["scanner", "door"]:
		var source := _lockout_control_source(action_id)
		if not is_instance_valid(source):
			continue
		var source_count := maxi(0, _lockout_source_trigger_count(source))
		var consumed := _scanner_trigger_consumed if action_id == "scanner" \
			else _door_trigger_consumed
		if consumed > source_count:
			if action_id == "scanner":
				_scanner_trigger_consumed = source_count
			else:
				_door_trigger_consumed = source_count
			changed = true
			consumed = source_count
		if source_count <= consumed:
			continue
		var gs = _get_game_state()
		var receipt: Dictionary = gs.get_interactable(str(source.get("data_id"))) \
			if gs != null and gs.has_interactable(str(source.get("data_id"))) else {}
		var actor := str(receipt.get("last_trigger_character", ""))
		var valid_receipt := source_count == consumed + 1 \
			and bool(receipt.get("one_shot", false)) \
			and bool(receipt.get("triggered", false)) \
			and not bool(receipt.get("enabled", true)) \
			and _lockout_actor_ready_at_source(source, actor)
		var outcome_already_committed := _chase_started if action_id == "scanner" \
			else _door_phase != DOOR_PHASE_OPEN
		if action_id == "scanner":
			_scanner_trigger_consumed = source_count
		else:
			_door_trigger_consumed = source_count
		changed = true
		if outcome_already_committed:
			continue
		if valid_receipt and action_id == "scanner":
			source.set("active_character", actor)
			_commit_tags_rejected(false)
			continue
		if valid_receipt and action_id == "door" and _chase_started:
			source.set("active_character", actor)
			_begin_service_door_close()
			continue
		if source.has_method("reset"):
			source.call("reset")
	return changed


func _reconcile_restored_seal_sources() -> bool:
	if str(_seal_transaction.get("phase", SEAL_TX_IDLE)) != SEAL_TX_IDLE:
		return false
	var changed := false
	for source_name in ["SealPadIn", "SealPadOut"]:
		var source := find_child(source_name, true, false) as Interactable
		if not is_instance_valid(source):
			continue
		var source_id := str(source.data_id)
		var source_count := maxi(0, _lockout_source_trigger_count(source))
		var consumed := int(_seal_trigger_consumed.get(source_id, 0))
		if consumed > source_count:
			_seal_trigger_consumed[source_id] = source_count
			consumed = source_count
			changed = true
		if source_count <= consumed:
			continue
		var gs = _get_game_state()
		var receipt: Dictionary = gs.get_interactable(source_id) \
			if gs != null and gs.has_interactable(source_id) else {}
		var actor := str(receipt.get("last_trigger_character", ""))
		var pad := _lockout_portal_for_name(
			str(source.get_meta("lockout_seal_pad_name", "")))
		var item_id := _hand_hushbloom(actor)
		var valid_receipt := source_count == consumed + 1 \
			and not bool(receipt.get("one_shot", true)) \
			and bool(receipt.get("triggered", false)) \
			and is_instance_valid(pad) and not pad.is_stunned() \
			and item_id != "" and _lockout_actor_ready_at_source(source, actor)
		if not valid_receipt:
			_seal_trigger_consumed[source_id] = source_count
			changed = true
			continue
		source.active_character = actor
		_seal_transaction = {
			"phase": SEAL_TX_RESERVED,
			"source_id": source_id,
			"source_trigger_count": source_count,
			"actor": actor,
			"item_id": item_id,
			"pad_name": str(pad.name),
			"stun_deadline": _get_scheduler_tick() + SEAL_SECS,
		}
		_publish_chase_authority()
		_finish_seal_transaction()
		changed = true
	return changed


func _retract_chase_presenter_to_defaults() -> void:
	_restoring_chase_authority = true
	_chase_started = false
	_pursuit_armed = false
	_scanner_trigger_consumed = 0
	_door_phase = DOOR_PHASE_OPEN
	_door_phase_start = -1.0
	_door_phase_deadline = -1.0
	_door_breacher = ""
	_door_trigger_consumed = 0
	_seal_trigger_consumed.clear()
	_clear_seal_transaction()
	_tyreg_phase = TYREG_PHASE_UNAVAILABLE
	_tyreg_join_actor = ""
	_tyreg_magazine_item_id = ""
	_clear_suppress_transaction()
	_decline_wave_fired = false
	_wave_count = 0
	_trip_refractory.clear()
	_fallen.clear()
	_recurring_epochs.clear()
	_one_shot_deadlines.clear()
	_one_shot_payloads.clear()
	_checkpoint_x = -1.0
	_gantry_phase = GANTRY_PHASE_STANDING
	_gantry_phase_start = -1.0
	_gantry_phase_deadline = -1.0
	if is_instance_valid(_service_door) and _service_door.has_method("reset"):
		_service_door.reset()
	_restore_pursuer_presenters([])
	_apply_restored_chase_presenters()
	_restoring_chase_authority = false


func _schedule_chase_one_shot_after(
		tag: String, delay: float, kind: String, payload: Dictionary) -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	var deadline := float(sched.get_current_tick()) + maxf(0.0, delay)
	_one_shot_deadlines[tag] = deadline
	_one_shot_payloads[tag] = {"kind": kind, "payload": payload.duplicate(true)}
	_schedule_chase_one_shot_at(tag, deadline)
	_publish_chase_authority()


func _schedule_chase_one_shot_at(tag: String, deadline: float) -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	sched.cancel_tag(tag)
	sched.schedule_after(maxf(0.0, deadline - float(sched.get_current_tick())),
		_fire_chase_one_shot.bind(tag), tag)


func _fire_chase_one_shot(tag: String) -> void:
	if not _one_shot_deadlines.has(tag) or not _one_shot_payloads.has(tag):
		return
	var descriptor: Dictionary = _one_shot_payloads[tag]
	_one_shot_deadlines.erase(tag)
	_one_shot_payloads.erase(tag)
	_publish_chase_authority()
	match str(descriptor.get("kind", "")):
		"wave":
			var payload: Dictionary = descriptor.get("payload", {})
			_spawn_wave(int(payload.get("count", 0)), bool(payload.get("near_party", false)),
				float(payload.get("base_x_override", -1.0)))
		"door_close":
			_commit_door_sealed()
		"door_breach":
			_commit_door_breached()
		"door_open":
			_commit_door_open()
		"gantry_land":
			_commit_gantry_landed()


func _arm_chase_recurring(
		tag: String, interval: float, callback: Callable, initial_delay: float) -> void:
	var sched = _get_scheduler()
	if sched == null or interval <= 0.0:
		return
	var created := false
	if not _recurring_epochs.has(tag):
		_recurring_epochs[tag] = float(sched.get_current_tick()) + maxf(0.0, initial_delay)
		created = true
	var current_tick := float(sched.get_current_tick())
	var deadline := _next_chase_recurring_tick(float(_recurring_epochs[tag]), interval)
	# Defense at the scheduler boundary: a recurring callback must never own a zero-delay successor,
	# even if a malformed restored epoch or a future arithmetic regression reaches this caller.
	if deadline <= current_tick:
		deadline = current_tick + interval
	sched.cancel_tag(tag)
	sched.schedule_after(deadline - current_tick, callback, tag)
	if created:
		_publish_chase_authority()


func _stop_chase_recurring(tag: String) -> void:
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag(tag)
	if _recurring_epochs.erase(tag):
		_publish_chase_authority()


func _next_chase_recurring_tick(epoch: float, interval: float) -> float:
	return _next_chase_recurring_tick_from(epoch, interval, _get_scheduler_tick())


## Resolve the next fixed-cadence boundary strictly after `now`. The scheduler executes callbacks
## whose deadline is equal to its current tick, so returning `now` here would let a self-rearming
## callback run forever inside one advance. The epsilon treats binary roundoff at an exact cadence
## boundary as a completed interval; the final guard is the non-negotiable scheduler invariant.
func _next_chase_recurring_tick_from(epoch: float, interval: float, now: float) -> float:
	if interval <= 0.0:
		return now + CHASE_RECUR_EPSILON
	if now < epoch - CHASE_RECUR_EPSILON:
		return epoch
	var completed := floori(((now - epoch) + CHASE_RECUR_EPSILON) / interval)
	var deadline := epoch + float(completed + 1) * interval
	if deadline <= now:
		deadline += interval
	return deadline


func _rearm_chase_callbacks() -> void:
	var recurring := {
		"chase_pursuit": [0.8, _pursuit_director],
		"chase_decline_watch": [1.0, _decline_watch],
		"chase_close_call": [1.0, _close_call_watch],
		"chase_hazards": [0.5, _hazard_poll],
		"chase_portal_follow": [1.0, _arm_portal_follow],
		"chase_door_hold": [0.5, _arm_door_hold],
		"chase_suppress": [1.2, _arm_suppress],
	}
	for tag_v in _recurring_epochs.keys():
		var tag := str(tag_v)
		if not recurring.has(tag):
			continue
		var spec: Array = recurring[tag]
		_arm_chase_recurring(tag, float(spec[0]), spec[1] as Callable, float(spec[0]))
	if _tyreg_help_accepted() and _tyreg_suppress_charge_count() > 0 \
			and not _recurring_epochs.has("chase_suppress"):
		_arm_chase_recurring("chase_suppress", 1.2, _arm_suppress, 1.2)
	for tag_v in _one_shot_deadlines.keys():
		var tag := str(tag_v)
		if _one_shot_payloads.has(tag):
			_schedule_chase_one_shot_at(tag, maxf(_get_scheduler_tick(), float(_one_shot_deadlines[tag_v])))


func _cancel_chase_scheduler_tags() -> void:
	var sched = _get_scheduler()
	if sched == null:
		return
	for tag in ["chase_wave_1", "chase_wave_2", "chase_decline_watch", "chase_close_call",
			"chase_pursuit", "chase_portal_follow", "chase_door_hold", "chase_suppress",
			"chase_directive", "chase_hazards", DOOR_PHASE_TAG, GANTRY_PHASE_TAG]:
		sched.cancel_tag(tag)


func _apply_restored_chase_presenters() -> void:
	_set_trench_blocked(_gantry_phase != GANTRY_PHASE_BRIDGED)
	_sync_gantry_presenter()
	_apply_service_door_topology(true)
	_sync_service_door_presenter()
	_sync_fallen_visuals()
	_wire_wash_sweep()
	_wire_lockout_external_traversal_signals()
	_sync_tyreg_presenter()
	_sync_tyreg_interaction_presenter()


func _restore_pursuer_presenters(saved_ids_raw: Array) -> void:
	var saved_ids: Array[String] = []
	for id_v in saved_ids_raw:
		var id := str(id_v)
		if id != "" and not saved_ids.has(id):
			saved_ids.append(id)
	var gs = _get_game_state()
	for idx in range(_enemies.size() - 1, -1, -1):
		var enemy = _enemies[idx]
		if not is_instance_valid(enemy) or str(enemy.char_id) not in saved_ids:
			_enemies.remove_at(idx)
			if is_instance_valid(enemy):
				enemy.queue_free()
	for id in saved_ids:
		if _enemy_by_id(id) != null or gs == null or not gs.characters.has(id):
			continue
		_spawn_enemy({"id": id, "class": "naturalizer", "pos": gs.get_position(id),
			"speed": NAT_SPEED, "detect": 0.0, "coop_exempt": true,
			"targets": ["aster", "peris"]}, gs)
		_wire_wave_nat(id)


func _portable_chase_float_map(source: Dictionary) -> Dictionary:
	var out := {}
	for key_v in source.keys():
		out[str(key_v)] = float(source[key_v])
	return out


func _portable_chase_int_map(source: Dictionary) -> Dictionary:
	var out := {}
	for key_v in source.keys():
		out[str(key_v)] = maxi(0, int(source[key_v]))
	return out


func _validated_chase_int_map(raw: Variant) -> Dictionary:
	var out := {}
	if not raw is Dictionary:
		return out
	for key_v in (raw as Dictionary).keys():
		var key := str(key_v)
		if key != "":
			out[key] = maxi(0, int((raw as Dictionary)[key_v]))
	return out


func _validated_chase_float_map(raw: Variant) -> Dictionary:
	var out := {}
	if not raw is Dictionary:
		return out
	for key_v in raw.keys():
		var value := float(raw[key_v])
		if is_finite(value):
			out[str(key_v)] = value
	return out

func get_preview_state() -> Dictionary:
	var st: Dictionary = super.get_preview_state()
	st["chase_started"] = _chase_started
	st["pursuit_armed"] = _pursuit_armed
	st["door_phase"] = _door_phase
	st["door_phase_progress"] = _door_transition_progress()
	st["door_blocking"] = _door_blocks_corridor()
	st["door_breacher"] = _door_breacher
	st["door_sealed"] = _door_blocks_corridor()
	st["tyreg_accepted"] = _tyreg_help_accepted()
	st["tyreg_phase"] = _tyreg_phase
	# Compatibility readout for QA/UI, derived only from the exact magazine currently owned by Tyreg.
	st["suppress_charges"] = _tyreg_suppress_charge_count()
	st["decline_wave"] = _decline_wave_fired
	# Compatibility readout for existing QA/UI consumers, now derived from canonical hand state.
	st["bloom_carry"] = _carried_hushbloom_count()
	st["pursuers"] = _enemies.size()
	st["gantry_phase"] = _gantry_phase
	st["gantry_progress"] = _gantry_fall_progress()
	st["bridge_down"] = _gantry_phase == GANTRY_PHASE_BRIDGED
	st["checkpoint_x"] = _checkpoint_x
	# the roguelite presenter's descent poll reads the generated-level key; the chase's wall rest
	# IS its shelter rest
	st["shelter_rested"] = bool(st.get("complete", false))
	return st

func get_decoration_audit() -> Dictionary:
	return _decoration_audit.duplicate(true)


func _exit_tree() -> void:
	if _traversal_signal_game_state != null and is_instance_valid(_traversal_signal_game_state) \
			and _traversal_signal_game_state.external_traversal_finished.is_connected(
				_on_lockout_external_traversal_finished):
		_traversal_signal_game_state.external_traversal_finished.disconnect(
			_on_lockout_external_traversal_finished)
	_traversal_signal_game_state = null
	var sched = _get_scheduler()
	if sched != null:
		for tag in ["chase_wave_1", "chase_wave_2", "chase_decline_watch", "chase_close_call",
				"chase_pursuit", "chase_portal_follow", "chase_door_hold", "chase_suppress",
				"chase_directive", "chase_hazards", DOOR_PHASE_TAG, GANTRY_PHASE_TAG]:
			sched.cancel_tag(tag)
		for enemy in _enemies:
			if is_instance_valid(enemy):
				sched.cancel_tag("enemy_%s" % enemy.name)
	super._exit_tree()
