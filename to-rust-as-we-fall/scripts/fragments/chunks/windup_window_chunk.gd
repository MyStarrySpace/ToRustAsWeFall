extends "res://scripts/scene_chunks/scene_chunk.gd"

## WINDUP WINDOW — FRAGMENT_IDEAS.md #4, built on the canonical Flare.
##
## One tension, one verb: SPACING. Every other fragment in the register asks you to read something
## the level is doing. This one asks you to watch what YOU are doing: the hazard is inert until the
## party crowds it, so the only thing that sets it off is your own formation.
##
## THE GEOMETRY IS THE LESSON. A portal carries ONE body at a time (the shipped portal rule), so a
## party sent to it as a group converges on the mouth apron and waits there together -- which is
## exactly the density a Flare bed reads. The convenient input (group-move everyone to the crossing)
## is the losing one. The answer is to hold members apart on the staging plates and send them
## singly, so the apron never has two bodies on it at once.
##
## Composes shipped systems only: PortalPad (including its one-at-a-time group queue) and the Flare.
## No new mechanism, and the Flare bed is greybox per the register's framing for micro tension
## chunks -- the plates are blockers and staging, not dressing.
##
## OWED, and deliberately not faked: the register's presented pressure is a Gnawer PACK, which gives
## the crossing a clock so you cannot simply take all day over it. No Gnawer class ships, so this
## builds the spacing core alone rather than substituting some other enemy and calling it the same
## design. The roster's other half -- "the savvy play is triggering it yourself (Myke's flame)" --
## is also absent on purpose: Inflame is explicitly unimplemented in canonical_character_ability.gd
## ("deliberately not fabricated here before its runtime contract is authored"), so the chunk leaves
## `pop_flare()` as a seam and offers the player no ignition it does not actually have.

const LANE_Z := 6.0
const MOUTH := Vector3(18.0, 0.0, LANE_Z)
const ACROSS := Vector3(24.5, 0.0, LANE_Z)
const EXIT_POS := Vector3(27.0, 0.0, LANE_Z)

## THE APRON MUST BE INSIDE THE KILL ZONE. A bed set further back gets triggered in passing: the
## party keeps walking to the mouth and the burst goes off behind them, so the wind-up you are
## supposed to react to is one you leave for free just by continuing to your destination. Every
## Flare here is placed so the mouth apron -- the one spot a queueing party has to stand -- sits
## WELL inside the burst, not on its lip.
##   dist(mouth, each) = 1.61, 1.61, 1.80   vs   burst_radius 3.2
## They still do not arm each other; a rooted bomb is not a body that crowds.
const FLARE_BED := [
	Vector3(17.2, 0.0, LANE_Z - 1.4),
	Vector3(17.2, 0.0, LANE_Z + 1.4),
	Vector3(16.2, 0.0, LANE_Z),
]

## Staging plates, set back beyond the bed's reach. Standing here is what "wait your turn" looks
## like, and the spacing between them is the spacing the fragment is teaching.
const STAGING := [
	Vector3(10.0, 0.0, LANE_Z - 3.0),
	Vector3(10.0, 0.0, LANE_Z),
	Vector3(10.0, 0.0, LANE_Z + 3.0),
]

const PARTY_IDS := ["aster", "peris", "endo"]

const SPAWNS := {
	"aster": Vector3(3.0, 0.0, LANE_Z),
	"peris": Vector3(3.0, 0.0, LANE_Z - 2.0),
	"endo": Vector3(3.0, 0.0, LANE_Z + 2.0),
}

var _phase := "ready"
var _flares: Array = []
var _portal
var _status_label: Label3D
var _bursts := 0
var _last_burst_hits: Array = []
var _last_burst_at := Vector3.ZERO

func _build_chunk() -> void:
	_add_floor(self, Vector3(14.0, -0.05, LANE_Z), Vector3(28.0, 0.1, 12.0), Color(0.12, 0.12, 0.15))
	for plate_pos in STAGING:
		_add_box(self, plate_pos + Vector3(0.0, 0.02, 0.0), Vector3(1.4, 0.05, 1.4),
			Color(0.26, 0.30, 0.34))
	# The gap the portal crosses. It is the reason the crossing is single-file rather than a walk.
	_add_box(self, Vector3(21.2, -0.4, LANE_Z), Vector3(4.0, 0.7, 11.0), Color(0.06, 0.06, 0.08))

	_spawn_flare_bed()
	_spawn_portal()

	var exit_door := _add_box(self, EXIT_POS + Vector3(0.0, 1.0, 0.0),
		Vector3(0.5, 2.0, 1.6), Color(0.46, 0.38, 0.26))
	_add_object_interactable(
		self, "CrossingExit", "Leave the crossing", EXIT_POS, "LEAVE",
		[exit_door], "", 0.6, true, 1.6, Interactable.InteractableType.INSPECTION
	).interacted.connect(_on_exit)

	_status_label = _add_label(self, "", Vector3(14.0, 3.2, LANE_Z), Color(0.78, 0.84, 0.96))

func _spawn_flare_bed() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	var index := 0
	for bed_pos in FLARE_BED:
		var bomb := Flare.new()
		bomb.name = "Flare_%d" % index
		bomb.position = bed_pos
		bomb._detection_targets.assign(PARTY_IDS)
		add_child(bomb)
		bomb.char_id = "flare_%d" % index
		bomb.game_state = gs
		if not gs.characters.has(bomb.char_id):
			gs.register_character(bomb.char_id, bomb.position, bomb.move_speed, {})
		if bomb.has_method("activate"):
			bomb.activate()
		bomb.burst.connect(_on_burst)
		_flares.append(bomb)
		index += 1

func _spawn_portal() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	var pad := PortalPad.new()
	pad.name = "CrossingPortal"
	add_child(pad)
	if pad.has_method("configure"):
		pad.configure(gs, MOUTH, ACROSS, 1.2)
	_portal = pad

## Declared from the design, before the body. --test-fragment-manifest proves the built scene has
## every one of these, and that each behavioural claim is backed by a test that actually exists.
func get_fragment_manifest() -> Dictionary:
	return {
		"components": [
			{"id": "flare_bed", "kind": "character", "char_prefix": "flare_", "count": 3},
			{"id": "crossing_portal", "kind": "node", "node_class": "PortalPad", "count": 1},
			{"id": "crossing_exit", "kind": "interactable", "node_name": "CrossingExit"},
		],
		"behaviours": [
			{
				"id": "lazy_play_fails",
				"claim": "sending the party to the crossing as a group sets the bed off AND costs hp",
				"test": "--test-windup-window-walk-across",
			},
			{
				"id": "singly_is_safe",
				"claim": "sending them one at a time leaves the bed inert",
				"test": "--test-windup-window",
			},
		],
	}

func configure_chunk(_config: Dictionary) -> void:
	pass

## The readouts a player needs and a test can assert: how crowded the apron is right now, and what
## the bed is doing about it.
func crowd_at_mouth() -> int:
	var gs = _get_game_state()
	if gs == null:
		return 0
	var count := 0
	for char_id in PARTY_IDS:
		if not gs.characters.has(char_id):
			continue
		var pos: Vector3 = gs.get_position(char_id)
		if Vector2(pos.x - MOUTH.x, pos.z - MOUTH.z).length() <= 2.6:
			count += 1
	return count

func flare_states() -> Array:
	var states: Array[String] = []
	for bomb in _flares:
		states.append(str(bomb.call("get_flare_state")))
	return states

func primed_count() -> int:
	var n := 0
	for bomb in _flares:
		if bool(bomb.call("is_primed")):
			n += 1
	return n

func burst_count() -> int:
	return _bursts

## The seam for a future ignition source. Not surfaced to the player: Inflame does not ship, and a
## click-to-detonate button would be a mechanism this project's canon has not authored.
func pop_flare(index: int) -> void:
	if index >= 0 and index < _flares.size():
		_flares[index].call("pop")

func _on_burst(at_position: Vector3, hit_ids: Array) -> void:
	_bursts += 1
	_last_burst_hits = hit_ids.duplicate()
	_last_burst_at = at_position

## What the last burst actually caught. A fragment that cannot say who it hit cannot be debugged when
## it fires but costs nobody anything.
func last_burst_hits() -> Array:
	return _last_burst_hits.duplicate()

func last_burst_at() -> Vector3:
	return _last_burst_at

func _members_across() -> int:
	var gs = _get_game_state()
	if gs == null:
		return 0
	var count := 0
	for char_id in PARTY_IDS:
		if gs.characters.has(char_id) and gs.get_position(char_id).x > 23.0:
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
	_bursts = 0

func headless_process(delta: float) -> void:
	_tick(delta)

func _process(delta: float) -> void:
	_tick(delta)

func _tick(_delta: float) -> void:
	if _phase == "ready" and _members_across() > 0:
		_phase = "crossing"
	if _status_label == null:
		return
	var primed := primed_count()
	_status_label.text = "ON THE APRON: %d  //  BED: %s" % [
		crowd_at_mouth(),
		("SWELLING (%d)" % primed) if primed > 0 else "quiet",
	]

func get_grid_data() -> Dictionary:
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [0.0, 0.0, 0.0],
		"cell_size": 1.0,
		"width": 30,
		"height": 14,
		"walkable_regions": [
			{"min": [1.0, 1.6], "max": [19.4, 10.4]},
			{"min": [23.0, 1.6], "max": [28.4, 10.4]},
		],
	}

func get_preview_camera_profile() -> Dictionary:
	return {
		"follow_offset": Vector3(8.0, 20.0, 13.0),
		"min_zoom": 0.5,
		"max_zoom": 2.0,
		"initial_zoom": 1.0,
		"reset_yaw": true,
	}

func get_preview_camera_recenter_target() -> Vector3:
	return Vector3(14.0, 0.0, LANE_Z)

func get_scene_title() -> String:
	return "Windup Window"

func get_scene_help() -> String:
	return "The bed by the crossing is inert until bodies crowd it, and the portal only takes one of you at a time -- so sending the party over as a group parks them together on the apron and sets it off. Wait apart on the plates and send them singly. Once it swells you have a couple of seconds, and stepping clear only saves whoever steps."

func get_default_character() -> String:
	return "aster"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate()

func get_preview_anchors() -> Dictionary:
	return {
		"portal_mouth": MOUTH,
		"portal_arrival": ACROSS,
		"staging_north": STAGING[0],
		"staging_centre": STAGING[1],
		"staging_south": STAGING[2],
		"crossing_exit": EXIT_POS,
	}

func get_preview_state() -> Dictionary:
	return {
		"contract_id": "windup_window_v1",
		"phase": _phase,
		"crowd": crowd_at_mouth(),
		"flares": flare_states(),
		"primed": primed_count(),
		"bursts": _bursts,
		"across": _members_across(),
	}
