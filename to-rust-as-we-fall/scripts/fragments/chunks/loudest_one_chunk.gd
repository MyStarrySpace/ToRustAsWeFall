extends "res://scripts/scene_chunks/scene_chunk.gd"

## THE LOUDEST ONE — FRAGMENT_IDEAS.md #3, built on the canonical Tangler.
##
## One tension, one verb: DISTRACT (hold the lock). A Tangler reads hyperexcitability, so it locks
## the loudest neural-active mover in the room. One member runs a noisy orbit and OWNS that lock; the
## other threads the thicket at a walk. The moment the decoy stops running, the lock jumps to whoever
## is loudest instead -- which is usually the crosser, mid-lane, with nowhere to be.
##
## THE DISTINCTION THAT IS THE WHOLE FRAGMENT (register, load-bearing): Scarpet does NOT help the
## crosser here. It masks the iron/metabolic channel, and a Tangler is reading the NEURAL one. There
## is deliberately no hide flora on the lane: "quiet" means WALKING, not concealed. A player who
## solves this by hiding has not learned the thing the fragment teaches, so the fragment does not
## offer the option.
##
## Composes shipped systems only: the Tangler (its lock rule, its long uncoil telegraph) and the
## shipped run/walk toggle, which is what "loudest" reads. No new mechanism.
##
## Greybox, per the register's own framing for micro tension chunks -- the thicket is blocking, not
## dressing, and the shapes are placeholders for library pieces.

const TANGLER_HOME := Vector3(11.0, 0.0, 6.5)
const LANE_Z := 3.0                       # the thicket lane the quiet one walks
const ORBIT_CENTRE := Vector3(11.0, 0.0, 10.0)  # open ground the decoy circles on
const EXIT_POS := Vector3(20.5, 0.0, 3.0)

const PARTY_IDS := ["aster", "peris"]

## West end, well outside the Tangler's 5.0 scan, so the fragment opens with it drifting rather than
## already reading somebody -- the lesson the gate fragment taught by shipping a boot pursuit.
const SPAWNS := {
	"aster": Vector3(2.0, 0.0, 6.0),
	"peris": Vector3(2.0, 0.0, 3.0),
}

var _phase := "ready"        # ready | crossed | complete
var _tangler
var _status_label: Label3D

func _build_chunk() -> void:
	_add_floor(self, Vector3(11.0, -0.05, 6.5), Vector3(22.0, 0.1, 13.0), Color(0.11, 0.13, 0.12))
	# The thicket: stems dense enough to read as a lane you thread, never as cover. They block the
	# lane's edges so the walk is committed -- you cannot drift out of the scan halfway across.
	for stem_x in [5.0, 7.0, 9.0, 13.0, 15.0, 17.0]:
		_add_box(self, Vector3(stem_x, 0.9, LANE_Z - 1.6), Vector3(0.35, 1.8, 0.35),
			Color(0.24, 0.30, 0.22))
		_add_box(self, Vector3(stem_x, 0.9, LANE_Z + 1.6), Vector3(0.35, 1.8, 0.35),
			Color(0.24, 0.30, 0.22))
	# No "WALK IT" / "RUN HERE" signage. Painting the rules into the play space is the P-SHOWN failure
	# this project keeps catching, and it is unnecessary here: two rows of stems ARE the lane, and open
	# ground is self-evidently open. The briefing surface says the rest; the floor shows it.

	var exit_door := _add_box(self, EXIT_POS + Vector3(0.0, 1.0, 0.0),
		Vector3(0.5, 2.0, 1.6), Color(0.46, 0.38, 0.26))
	_add_object_interactable(
		self, "ThicketExit", "Leave through the far gap", EXIT_POS, "LEAVE",
		[exit_door], "", 0.6, true, 1.6, Interactable.InteractableType.INSPECTION
	).interacted.connect(_on_exit)

	_status_label = _add_label(self, "", Vector3(11.0, 3.2, 6.5), Color(0.74, 0.85, 0.96))
	_spawn_tangler()

## It roams its own patch rather than patrolling a line: a Tangler is not enforcement, it is a thing
## in the thicket that notices you. Roam is a scanning state, so its lock stays live while it drifts.
func _spawn_tangler() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	var enemy := Tangler.new()
	enemy.name = "ThicketTangler"
	enemy.position = TANGLER_HOME
	enemy._detection_targets.assign(PARTY_IDS)
	add_child(enemy)
	enemy.char_id = "thicket_tangler"
	enemy.game_state = gs
	if not gs.characters.has("thicket_tangler"):
		gs.register_character("thicket_tangler", enemy.position, enemy.move_speed,
			{"detection_range": float(enemy.detection_range)})
	if enemy.has_method("activate"):
		enemy.activate()
	if enemy.has_method("set_roam"):
		enemy.set_roam(TANGLER_HOME, 2.2)
	_tangler = enemy

func configure_chunk(_config: Dictionary) -> void:
	pass

## Who currently owns the lock, and whether anybody is paying to hold it. A fragment that cannot say
## this cannot teach it.
func get_lock_holder() -> String:
	if _tangler == null:
		return ""
	return str(_tangler.call("get_locked_target"))

func _running_members() -> Array:
	var gs = _get_game_state()
	var loud: Array[String] = []
	if gs == null:
		return loud
	for char_id in PARTY_IDS:
		if gs.characters.has(char_id) and gs.has_method("is_running") \
				and bool(gs.call("is_running", char_id)):
			loud.append(char_id)
	return loud

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

func headless_process(delta: float) -> void:
	_tick(delta)

func _process(delta: float) -> void:
	_tick(delta)

func _tick(_delta: float) -> void:
	if _phase == "ready" and _members_across() > 0:
		_phase = "crossed"
	if _status_label == null:
		return
	var loud := _running_members()
	_status_label.text = "LOCK: %s  //  LOUD: %s" % [
		get_lock_holder().to_upper() if get_lock_holder() != "" else "—",
		", ".join(loud).to_upper() if not loud.is_empty() else "nobody",
	]

func get_grid_data() -> Dictionary:
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [0.0, 0.0, 0.0],
		"cell_size": 1.0,
		"width": 23,
		"height": 14,
		"walkable_regions": [
			{"min": [1.0, 1.0], "max": [21.6, 12.4]},
		],
	}

func get_preview_camera_profile() -> Dictionary:
	# Same lesson as the plaza: the fragment runs west->east and the party enters from the west, so a
	# camera centred on them throws the room off to the right. Offset east.
	return {
		"follow_offset": Vector3(7.0, 18.0, 12.0),
		"min_zoom": 0.5,
		"max_zoom": 2.0,
		"initial_zoom": 1.0,
		"reset_yaw": true,
	}

func get_preview_camera_recenter_target() -> Vector3:
	return Vector3(11.0, 0.0, 6.5)

func get_scene_title() -> String:
	return "The Loudest One"

func get_scene_help() -> String:
	return "The thing in the thicket reads noise, not iron -- hiding does nothing here. One of you RUNS on the open ground to own its attention; the other WALKS the thicket lane. Stop running and the lock jumps to whoever is loudest instead, which is whoever is mid-lane."

func get_default_character() -> String:
	return "aster"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate()

func get_preview_anchors() -> Dictionary:
	return {
		"tangler_home": TANGLER_HOME,
		"orbit_centre": ORBIT_CENTRE,
		"lane_west": Vector3(4.0, 0.0, LANE_Z),
		"lane_east": Vector3(18.0, 0.0, LANE_Z),
		"thicket_exit": EXIT_POS,
	}

func get_preview_state() -> Dictionary:
	return {
		"contract_id": "loudest_one_v1",
		"phase": _phase,
		"lock": get_lock_holder(),
		"loud": _running_members(),
		"across": _members_across(),
		"tangler_state": str(_tangler.call("get_state")) if _tangler != null else "",
	}
