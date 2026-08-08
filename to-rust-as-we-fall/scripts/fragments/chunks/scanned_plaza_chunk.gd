extends "res://scripts/scene_chunks/scene_chunk.gd"

## THE SCANNED PLAZA THAT KEEPS ITS PATROL — FRAGMENT_IDEAS.md #21, base config (one route, wide
## mat, teaching). A typed SINK of capacity 1: a fixed enforcement route never leaves its
## jurisdiction, so this plaza permanently absorbs one Naturalizer.
##
## The plaza prices its two crossings differently and shows you both before you commit:
##   OPEN LANE  — fast, straight, and inside the scan. Free, if you time the sweep.
##   CANDID MAT — scan-blind (CONCEAL_FULL) but it charges health by the tick. Costs HP, not the run.
## A Scarpet margin at the south edge is medium cover with no drain: the place you wait out a period
## when the mat has taken enough. Adjacency lane -> mat -> margin is a placement invariant, so the
## canonical recovery (break to cover) always routes you onto the expensive lane rather than a wall.
##
## STAGING CORRECTION honoured (GDD 7.3, and load-bearing): a Naturalizer's equipment stops working on
## colonized ground, so patrols SKIP it. The route therefore walks CLEAN ground along the north lane
## and scans across and down into the colonized aisle -- ECOLOGY_COMBOS Card 2 staging. The invariant
## that follows: NO mat cell may lie on the walked route. The mat is the roster's own bypass, not a
## lane inside the patrol's footprint.
##
## Composes shipped systems only: the Naturalizer subclass, candid_zone.gd (DoT + CONCEAL_FULL),
## scarpet.gd (medium tier), and the loader's shared concealment pass, which asks each zone whether it
## covers a position every frame -- no per-chunk concealment wiring. The register's unravel-lane
## configuration is deliberately NOT built here: it needs terrain damage applied to enemy bodies,
## which does not ship, and it is a second verb besides.

const PATROL_Z := 2.5                       # the clean north lane the enforcement route walks
const OPEN_LANE_Z := 4.5                    # fast, scanned
const MAT_CENTRE := Vector3(12.5, 0.0, 7.0) # scan-blind, priced in hp/tick
const MAT_HALF := Vector2(5.2, 1.5)
const MARGIN_WEST := Vector3(4.0, 0.0, 9.8)
const MARGIN_EAST := Vector3(20.6, 0.0, 9.8)
const EXIT_POS := Vector3(23.4, 0.0, 9.8)

const MAT_DOT_PER_SEC := 4.0
const SCAN_RANGE := 6.0

const PARTY_IDS := ["aster", "peris"]

## South-west, outside the sweep's reach at its nearest approach. The gate fragment taught this the
## hard way: a party spawned inside detection opens the scene already caught.
const SPAWNS := {
	"aster": Vector3(2.4, 0.0, 9.8),
	"peris": Vector3(3.5, 0.0, 9.8),
}

var _phase := "ready"          # ready | crossed | complete
var _sentry
var _mat: CandidZone
var _status_label: Label3D
var _mat_ticks := 0.0

func _build_chunk() -> void:
	_add_floor(self, Vector3(12.5, -0.05, 6.0), Vector3(25.0, 0.1, 10.0), Color(0.12, 0.13, 0.15))
	# The clean perimeter the route walks, tinted apart from the colonized aisle so the "why does it
	# never step on the mat" question answers itself from the floor.
	_add_box(self, Vector3(12.5, 0.01, PATROL_Z), Vector3(21.0, 0.04, 2.0), Color(0.22, 0.21, 0.18))
	_add_label(self, "ENFORCEMENT LANE", Vector3(12.5, 2.0, PATROL_Z - 1.4), Color(0.92, 0.66, 0.42))
	_add_label(self, "OPEN LANE // SCANNED", Vector3(12.5, 1.6, OPEN_LANE_Z), Color(0.86, 0.84, 0.62))

	_mat = CandidZone.new()
	_mat.name = "PlazaCandidMat"
	_mat.configure(MAT_CENTRE, MAT_HALF, MAT_DOT_PER_SEC)
	add_child(_mat)

	for margin in [MARGIN_WEST, MARGIN_EAST]:
		var mat := Scarpet.new()
		mat.name = "PlazaScarpet_%d" % int(margin.x)
		mat.configure(margin, 1.9)
		add_child(mat)

	# A visible way out, for the same reason as the gate's: an interactable with no mesh has nothing
	# to outline, so it never lights on hover. Click-gated (INSPECTION), not proximity.
	var exit_door := _add_box(self, EXIT_POS + Vector3(0.0, 1.0, 0.0),
		Vector3(0.5, 2.0, 1.6), Color(0.46, 0.38, 0.26))
	_add_object_interactable(
		self, "PlazaExit", "Leave the plaza", EXIT_POS, "LEAVE",
		[exit_door], "", 0.6, true, 1.6, Interactable.InteractableType.INSPECTION
	).interacted.connect(_on_exit)

	_status_label = _add_label(self, "", Vector3(12.5, 3.2, 6.0), Color(0.74, 0.85, 0.96))
	_spawn_patrol()

## The absorbed body. Its route is FIXED and walks only clean ground; the scan reaches across and down
## into the aisle, which is what makes the open lane a timing problem and the mat worth its price.
func _spawn_patrol() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	var enemy := (Naturalizer.new() as Enemy)
	enemy.name = "PlazaEnforcement"
	enemy.position = Vector3(4.0, 0.0, PATROL_Z)
	enemy.move_speed = 2.0
	enemy.detection_range = SCAN_RANGE
	enemy._detection_targets.assign(PARTY_IDS)
	add_child(enemy)
	enemy.char_id = "plaza_enforcement"
	enemy.game_state = gs
	if not gs.characters.has("plaza_enforcement"):
		gs.register_character("plaza_enforcement", enemy.position, enemy.move_speed,
			{"detection_range": float(enemy.detection_range)})
	if enemy.has_method("activate"):
		enemy.activate()
	if enemy.has_method("set_patrol"):
		var route: Array[Vector3] = [
			Vector3(4.0, 0.0, PATROL_Z),
			Vector3(21.0, 0.0, PATROL_Z),
		]
		enemy.set_patrol(route)
	_sentry = enemy

func configure_chunk(_config: Dictionary) -> void:
	pass

## The invariant the staging correction demands, exposed so a test can assert it rather than trusting
## the authored numbers: no cell the route walks may be colonized.
func mat_clears_patrol_route() -> bool:
	if _mat == null:
		return false
	var mat_north := MAT_CENTRE.z - MAT_HALF.y
	return mat_north > PATROL_Z + 0.5

func _members_across() -> int:
	var gs = _get_game_state()
	if gs == null:
		return 0
	var count := 0
	for char_id in PARTY_IDS:
		if gs.characters.has(char_id) and gs.get_position(char_id).x > 19.0:
			count += 1
	return count

func _on_exit() -> void:
	if _phase == "complete":
		return
	if _members_across() < PARTY_IDS.size():
		return
	_phase = "complete"

func reset_preview_state() -> void:
	_phase = "ready"
	_mat_ticks = 0.0

func headless_process(delta: float) -> void:
	_tick(delta)

func _process(delta: float) -> void:
	_tick(delta)

func _tick(delta: float) -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	if _phase == "ready" and _members_across() > 0:
		_phase = "crossed"
	var on_mat: Array[String] = []
	if _mat != null:
		for char_id in PARTY_IDS:
			if gs.characters.has(char_id) and _mat.covers(gs.get_position(char_id)):
				on_mat.append(char_id)
	if not on_mat.is_empty():
		_mat_ticks += delta
	if _status_label != null:
		_status_label.text = "PATROL %s  //  ON MAT: %s" % [
			(str(_sentry.get_state()).to_upper() if _sentry != null else "—"),
			", ".join(on_mat).to_upper() if not on_mat.is_empty() else "nobody",
		]

func get_grid_data() -> Dictionary:
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [0.0, 0.0, 0.0],
		"cell_size": 1.0,
		"width": 26,
		"height": 12,
		"walkable_regions": [
			{"min": [1.0, 1.5], "max": [24.4, 10.6]},
		],
	}

func get_preview_camera_profile() -> Dictionary:
	# The plaza runs west->east and the party must enter from the west (anywhere nearer the middle is
	# inside the sweep), so a camera centred on them throws the whole composition off to the right,
	# under the overlay panel. Offsetting the camera EAST puts the party at frame-left and the plaza
	# they have to read across the open middle of the screen instead.
	return {
		"follow_offset": Vector3(8.0, 19.0, 12.0),
		"min_zoom": 0.5,
		"max_zoom": 2.0,
		"initial_zoom": 1.0,
		"reset_yaw": true,
	}

func get_preview_camera_recenter_target() -> Vector3:
	return Vector3(12.5, 0.0, 6.0)

func get_scene_title() -> String:
	return "The Scanned Plaza"

func get_scene_help() -> String:
	return "A fixed enforcement route owns this plaza and never leaves it. Cross west to east: the open lane is fast but inside the scan, so time the sweep; the pale Candid mat is scan-blind but charges health every tick. The dark Scarpet margins are medium cover with no drain -- wait out a period there when the mat has taken enough."

func get_default_character() -> String:
	return "aster"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate()

func get_preview_anchors() -> Dictionary:
	return {
		"candid_mat": MAT_CENTRE,
		"margin_west": MARGIN_WEST,
		"margin_east": MARGIN_EAST,
		"plaza_exit": EXIT_POS,
	}

func get_preview_state() -> Dictionary:
	var gs = _get_game_state()
	var on_mat: Array[String] = []
	if gs != null and _mat != null:
		for char_id in PARTY_IDS:
			if gs.characters.has(char_id) and _mat.covers(gs.get_position(char_id)):
				on_mat.append(char_id)
	return {
		"contract_id": "scanned_plaza_v1",
		"phase": _phase,
		"on_mat": on_mat,
		"mat_seconds": _mat_ticks,
		"across": _members_across(),
		"patrol_state": str(_sentry.get_state()) if _sentry != null else "",
		"mat_clears_route": mat_clears_patrol_route(),
	}
