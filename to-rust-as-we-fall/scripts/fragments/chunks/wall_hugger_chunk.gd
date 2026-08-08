extends "res://scripts/scene_chunks/scene_chunk.gd"

## WALL-HUGGER'S LAMENT — FRAGMENT_IDEAS.md #2, built on the canonical Spiker.
##
## One tension, one verb: POSITION under a moving safe cell. It inverts the instinct every corridor
## teaches. Acid vents run BOTH walls on an alternating cadence, so the wall is periodically the worst
## place to be; the open middle is permanently dry but a rooted Spiker watches it. Safe ground is
## neither -- it is the MOVING INTERSECTION of "this wall is not venting right now" and "I am out of
## the turret's sight", and it slides down the corridor as the cadence flips.
##
## THE TWO REGISTERS ARE BOTH REQUIRED (register, and it is what makes this a pair puzzle):
##   WHEN  — the vent cadence. The channels telegraph before they open, so the beat is readable.
##   WHERE — the LOS break. The Spiker's connection dies the instant sight is broken, and the flora
##           clumps along the walls are what break it. Strip either register and the corridor is
##           unsolvable, which is the point.
##
## Composes shipped systems only: Channel (the cadence band, reskinned as a wall vent exactly as the
## register instructs -- NOT Crust AI), the Spiker, Scarpet, and the grid's own sight blockers. The
## flora clumps register sight blockers on their cells, which is what makes the roster's stated
## counter -- "break line of sight with terrain, Capbage, or Scarpet" -- true against this turret
## rather than merely claimed.

const NORTH_VENT_Z := 3.0
const SOUTH_VENT_Z := 9.0
const LANE_Z := 6.0
const VENT_HALF_Z := 1.2
const VENT_PERIOD := 6.0
const VENT_DURATION := 2.4

const SPIKER_POST := Vector3(20.0, 0.0, LANE_Z)
const EXIT_POS := Vector3(25.0, 0.0, LANE_Z)

## Two clumps inside the turret's reach, one against each wall, so whichever wall is currently dry
## also offers the sight break. That coincidence IS the safe cell.
const COVER_CLUMPS := [
	Vector3(14.5, 0.0, NORTH_VENT_Z + 1.6),
	Vector3(17.5, 0.0, SOUTH_VENT_Z - 1.6),
]

const PARTY_IDS := ["aster", "peris"]

const SPAWNS := {
	"aster": Vector3(2.0, 0.0, LANE_Z),
	"peris": Vector3(2.0, 0.0, LANE_Z - 1.2),
}

var _phase := "ready"
var _spiker
var _north_vent
var _south_vent
var _status_label: Label3D

func _build_chunk() -> void:
	_add_floor(self, Vector3(13.0, -0.05, LANE_Z), Vector3(26.0, 0.1, 10.0), Color(0.13, 0.12, 0.14))
	# The vent lips read as wall furniture so the danger has a face even between openings.
	for lip_x in range(4, 24, 3):
		_add_box(self, Vector3(float(lip_x), 0.35, NORTH_VENT_Z - 1.3),
			Vector3(1.6, 0.7, 0.3), Color(0.34, 0.24, 0.20))
		_add_box(self, Vector3(float(lip_x), 0.35, SOUTH_VENT_Z + 1.3),
			Vector3(1.6, 0.7, 0.3), Color(0.34, 0.24, 0.20))

	_north_vent = _make_vent("north", NORTH_VENT_Z, 0.0)
	_south_vent = _make_vent("south", SOUTH_VENT_Z, VENT_PERIOD * 0.5)

	_add_cover_clumps()
	_spawn_spiker()

	var exit_door := _add_box(self, EXIT_POS + Vector3(0.0, 1.0, 0.0),
		Vector3(0.5, 2.0, 1.6), Color(0.46, 0.38, 0.26))
	_add_object_interactable(
		self, "CorridorExit", "Leave the corridor", EXIT_POS, "LEAVE",
		[exit_door], "", 0.6, true, 1.6, Interactable.InteractableType.INSPECTION
	).interacted.connect(_on_exit)

	_status_label = _add_label(self, "", Vector3(13.0, 3.0, LANE_Z), Color(0.76, 0.86, 0.96))

## A vent is a Channel: a band with a period, a duration and a phase, which telegraphs before it
## opens. The two walls run half a period apart, so exactly one of them is dangerous at a time and the
## safe side keeps swapping.
func _make_vent(tag: String, z_center: float, phase: float):
	var vent = Channel.new()
	vent.name = "Vent_%s" % tag
	vent.configure(13.0, 11.0, VENT_HALF_Z, VENT_PERIOD, VENT_DURATION, phase,
		"wallhugger_%s" % tag, z_center)
	add_child(vent)
	if vent.has_method("start"):
		vent.start(_get_scheduler(), _get_game_state())
	return vent

## Scarpet clumps that ALSO break sight. Concealment alone would not save anyone here: a Spiker reads
## line of sight off the grid, so the clumps register sight blockers on their own cells. Without this
## the roster's named counter would be a claim the fragment does not honour.
func _add_cover_clumps() -> void:
	var gs = _get_game_state()
	for clump_pos in COVER_CLUMPS:
		var mat := Scarpet.new()
		mat.name = "Cover_%d" % int(clump_pos.x)
		mat.configure(clump_pos, 1.7)
		add_child(mat)
		if gs != null and gs.grid != null and gs.grid.has_method("add_sight_blocker"):
			var cell: Vector2i = gs.grid.world_to_grid(clump_pos)
			for dx in [-1, 0, 1]:
				gs.grid.add_sight_blocker(Vector2i(cell.x + dx, cell.y))

func _spawn_spiker() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	var turret := Spiker.new()
	turret.name = "LaneSpiker"
	turret.position = SPIKER_POST
	turret._detection_targets.assign(PARTY_IDS)
	add_child(turret)
	turret.char_id = "lane_spiker"
	turret.game_state = gs
	if not gs.characters.has("lane_spiker"):
		gs.register_character("lane_spiker", turret.position, turret.move_speed,
			{"detection_range": float(turret.detection_range)})
	if turret.has_method("activate"):
		turret.activate()
	_spiker = turret

## Declared from the design, before the body. The vents are declared "water" specifically: a fluid
## body that exists in the data layer but renders nothing is the failure mode this kind exists to
## catch, because the whole corridor is unreadable if the player cannot SEE which wall is running.
func get_fragment_manifest() -> Dictionary:
	return {
		"components": [
			{"id": "wall_vents", "kind": "water", "node_class": "Channel", "count": 2},
			{"id": "lane_spiker", "kind": "character", "char_prefix": "lane_spiker", "count": 1},
			{"id": "cover_clumps", "kind": "node", "node_class": "Scarpet", "count": 2},
			{"id": "corridor_exit", "kind": "interactable", "node_name": "CorridorExit"},
		],
		"behaviours": [
			{
				"id": "alternating_vents",
				"claim": "the two walls never vent at the same time, so there is always a dry side",
				"test": "--test-wall-hugger",
			},
			{
				"id": "cover_breaks_sight",
				"claim": "a body behind a clump breaks the turret's connection",
				"test": "--test-wall-hugger",
			},
		],
	}

func configure_chunk(_config: Dictionary) -> void:
	pass

## The safe cell, stated as data so a test can assert it rather than trusting the layout: a wall side
## is safe only while its vent is shut, and the lane is safe only where the turret cannot see.
func vent_open(side: String) -> bool:
	var vent = _north_vent if side == "north" else _south_vent
	return vent != null and bool(vent.call("is_flooding"))

func spiker_connection() -> String:
	if _spiker == null:
		return ""
	return str(_spiker.call("get_connection_target"))

func _members_across() -> int:
	var gs = _get_game_state()
	if gs == null:
		return 0
	var count := 0
	for char_id in PARTY_IDS:
		if gs.characters.has(char_id) and gs.get_position(char_id).x > 23.5:
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

func headless_process(delta: float) -> void:
	_tick(delta)

func _process(delta: float) -> void:
	_tick(delta)

func _tick(_delta: float) -> void:
	if _phase == "ready" and _members_across() > 0:
		_phase = "crossed"
	if _status_label == null:
		return
	var venting := []
	if vent_open("north"):
		venting.append("NORTH")
	if vent_open("south"):
		venting.append("SOUTH")
	_status_label.text = "VENTING: %s  //  TURRET: %s" % [
		", ".join(venting) if not venting.is_empty() else "neither",
		spiker_connection().to_upper() if spiker_connection() != "" else "no lock",
	]

func get_grid_data() -> Dictionary:
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [0.0, 0.0, 0.0],
		"cell_size": 1.0,
		"width": 28,
		"height": 12,
		"walkable_regions": [
			{"min": [1.0, 1.6], "max": [26.4, 10.4]},
		],
	}

func get_preview_camera_profile() -> Dictionary:
	return {
		"follow_offset": Vector3(8.0, 19.0, 12.0),
		"min_zoom": 0.5,
		"max_zoom": 2.0,
		"initial_zoom": 1.0,
		"reset_yaw": true,
	}

func get_preview_camera_recenter_target() -> Vector3:
	return Vector3(13.0, 0.0, LANE_Z)

func get_scene_title() -> String:
	return "Wall-Hugger's Lament"

func get_scene_help() -> String:
	return "Both walls vent acid, half a beat apart, so the safe wall keeps swapping -- and the dry middle is watched by a rooted turret whose charge only lands if it holds sight of you. Read the vent beat for WHEN and use the wall clumps to break its sight for WHERE. Neither read alone gets you down the corridor."

func get_default_character() -> String:
	return "aster"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate()

func get_preview_anchors() -> Dictionary:
	return {
		"spiker_post": SPIKER_POST,
		"cover_north": COVER_CLUMPS[0],
		"cover_south": COVER_CLUMPS[1],
		"corridor_exit": EXIT_POS,
	}

func get_preview_state() -> Dictionary:
	return {
		"contract_id": "wall_hugger_v1",
		"phase": _phase,
		"north_venting": vent_open("north"),
		"south_venting": vent_open("south"),
		"turret_lock": spiker_connection(),
		"across": _members_across(),
	}
