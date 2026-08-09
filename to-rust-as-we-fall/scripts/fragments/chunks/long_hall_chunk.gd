extends "res://scripts/scene_chunks/scene_chunk.gd"

## LONG HALL — a route priced in HP, and the safe way round that costs time instead.
##
## The open-world run offers several ways to the same place and the player chooses by choosing a
## route. This fragment is the smallest honest instance of that: two mouths off one plaza, each
## advertising its fee before you commit. The hall is short and costs blood; the long way is free and
## costs minutes.
##
## THE FEE IS ARITHMETIC. The hall's length comes from `RiskLane.length_for_strikes(1)` — the shortest
## corridor whose price is exactly one connection — so the geometry IS the sum rather than a number
## someone tuned by feel. Running it drains the whole stamina bar a few units short of cover; the legs
## give out, GameState drops the runner to walking pace, the chaser closes, one charge lands, and the
## Capbage takes them. Stamina is the mechanism; HP is the price.
##
## Composes shipped systems only: the run toggle and its stamina drain, the enemy pursuit/charge cycle,
## Capbage tight-hide concealment, and dynamic blockers for the two mouths. Greybox — dressing is a
## canon consultation, not part of the arithmetic.

const RiskLaneScript := preload("res://scripts/generation/risk_lane.gd")
const EnemyScript := preload("res://scripts/game/ai/enemy.gd")
const CapbageScript := preload("res://scripts/game/objects/capbage.gd")

## A route is a solo dash. One runner means the fee is charged at one pace: a mixed party walks at
## several, and a lane cut for one of them undercharges or overcharges every other.
const PARTY_IDS := ["aster"]
const PURSUER_ID := "hall_pursuer"

const HALL_Z := 7.0
const SAFE_Z := 2.0
const PLAZA_MIN_X := 1.0
const MOUTH_X := 9.0

const SPAWNS := {
	"aster": Vector3(3.0, 0.0, 7.0),
}

var _hall_length := 0.0
var _hall_price: Dictionary = {}
var _hide_x := 0.0
var _rejoin_x := 0.0
var _grid_width := 0
var _phase := "choosing"          # choosing | hall | safe | hidden | complete
var _strikes := 1
var _committed_route := ""
var _pursuer: Node3D
var _capbage: Capbage
var _status_label: Label3D
var _hp_at_commit: Dictionary = {}
var _sealed_cells: Dictionary = {}   # route id -> Array[Vector2i] currently blocking that mouth


func configure_chunk(config: Dictionary) -> void:
	_strikes = maxi(1, int(config.get("strikes", 1)))
	_reprice()


## Price the lane, then take the geometry from that price. The profile is read off the live world
## where the world is available, so the corridor is cut for the pace this party actually walks and
## the damage this chaser actually deals rather than for a set of constants copied into the level.
func _reprice() -> void:
	var profile: Dictionary = RiskLaneScript.profile_from_world(
		_get_game_state(), _pursuer_template(), PARTY_IDS)
	_hall_price = RiskLaneScript.price(float((RiskLaneScript.length_for_strikes(
		_strikes, profile) as Dictionary)["lane_length"]), profile)
	_hall_length = float(_hall_price["lane_length"])


func _pursuer_template():
	if _pursuer != null and is_instance_valid(_pursuer):
		return _pursuer
	return null


func _build_chunk() -> void:
	# The party registers before the chunk builds, so this is the first moment the real pace is
	# knowable; the corridor is cut from that price rather than from the opening estimate.
	_reprice()
	_hide_x = MOUTH_X + _hall_length
	_rejoin_x = _hide_x + 4.0
	_grid_width = int(ceilf(_rejoin_x)) + 5

	_add_floor(self, Vector3(_grid_width * 0.5, -0.05, 5.0),
		Vector3(float(_grid_width), 0.1, 12.0), Color(0.13, 0.12, 0.14))
	_build_walls()
	_build_route_board()
	_build_mouths()
	_build_hide()
	_build_exit()
	_status_label = _add_label(self, "", Vector3(4.0, 3.2, 5.0), Color(0.78, 0.86, 0.96))
	_refresh_status()
	var gs = _get_game_state()
	if gs != null and gs.has_signal("stat_changed") \
			and not gs.stat_changed.is_connected(_on_stat_changed):
		gs.stat_changed.connect(_on_stat_changed)


## The band between the two corridors, plus the outer shell. The hall has no cover along its whole
## run: that absence is the mechanism, so nothing may be placed inside it.
func _build_walls() -> void:
	var span := float(_grid_width)
	_add_box(self, Vector3(span * 0.5, 1.0, 4.5), Vector3(span - 12.0, 2.0, 1.0),
		Color(0.2, 0.19, 0.22), Color.BLACK, 0.0, "RouteDivider")
	_add_box(self, Vector3(span * 0.5, 1.0, 0.2), Vector3(span, 2.0, 0.4),
		Color(0.18, 0.17, 0.2), Color.BLACK, 0.0, "NorthShell")
	_add_box(self, Vector3(span * 0.5, 1.0, 9.8), Vector3(span, 2.0, 0.4),
		Color(0.18, 0.17, 0.2), Color.BLACK, 0.0, "SouthShell")


func _build_route_board() -> void:
	var board := _add_box(self, Vector3(4.0, 1.1, 5.0), Vector3(0.3, 1.6, 1.4),
		Color(0.32, 0.3, 0.26), Color(0.1, 0.28, 0.14), 0.6, "RouteBoardPlate")
	_add_object_interactable(
		self, "RouteBoard", "Read the route board", Vector3(4.0, 0.0, 5.0), "READ",
		[board], "", 0.6, false, 1.4, Interactable.InteractableType.INSPECTION
	).interacted.connect(_on_board_read)


## Each mouth is sealed until it is chosen, so a route cannot be entered without being priced first.
func _build_mouths() -> void:
	var hall_plate := _add_box(self, Vector3(MOUTH_X, 1.0, HALL_Z), Vector3(0.4, 2.0, 3.0),
		Color(0.4, 0.22, 0.2), Color(0.5, 0.12, 0.1), 0.5, "HallMouthPlate")
	_add_object_interactable(
		self, "HallMouth", "Take the hall — %d HP" % int(_hall_price.get("hp_cost", 0.0)),
		Vector3(MOUTH_X - 1.2, 0.0, HALL_Z), "TAKE THE HALL",
		[hall_plate], "", 0.8, true, 1.5, Interactable.InteractableType.INSPECTION
	).interacted.connect(_on_hall_taken)
	_seal_route("hall", _hall_mouth_cells())

	var safe_plate := _add_box(self, Vector3(MOUTH_X, 1.0, SAFE_Z), Vector3(0.4, 2.0, 3.0),
		Color(0.22, 0.3, 0.36), Color(0.1, 0.3, 0.4), 0.5, "SafeMouthPlate")
	_add_object_interactable(
		self, "SafeMouth", "Take the long way — no blood, no hurry",
		Vector3(MOUTH_X - 1.2, 0.0, SAFE_Z), "TAKE THE LONG WAY",
		[safe_plate], "", 0.8, true, 1.5, Interactable.InteractableType.INSPECTION
	).interacted.connect(_on_safe_taken)
	_seal_route("safe", _safe_mouth_cells())


func _build_hide() -> void:
	_capbage = CapbageScript.new()
	_capbage.name = "HallCapbage"
	# Cover is the END of the hall, not a point inside it: a runner who has paid the fee should not
	# lose the lane to a last stride. The head sits back from the far wall so its whole mouth counts.
	_capbage.configure(_get_game_state(), Vector3(_hide_x, 0.0, HALL_Z), 3.5)
	_capbage.description = "Tuck into the Capbage at the end of the hall"
	add_child(_capbage)


func _build_exit() -> void:
	var arch := _add_box(self, Vector3(_rejoin_x, 1.1, 5.0), Vector3(0.5, 2.2, 1.8),
		Color(0.46, 0.38, 0.26), Color.BLACK, 0.0, "ExitArch")
	_add_object_interactable(
		self, "HallExit", "Leave by the junction", Vector3(_rejoin_x, 0.0, 5.0), "LEAVE",
		[arch], "", 0.6, true, 1.6, Interactable.InteractableType.INSPECTION
	).interacted.connect(_on_exit)


func _hall_mouth_cells() -> Array:
	return [Vector2i(int(MOUTH_X), 6), Vector2i(int(MOUTH_X), 7), Vector2i(int(MOUTH_X), 8)]


func _safe_mouth_cells() -> Array:
	return [Vector2i(int(MOUTH_X), 1), Vector2i(int(MOUTH_X), 2), Vector2i(int(MOUTH_X), 3)]


func _seal_route(route_id: String, cells: Array) -> void:
	_sealed_cells[route_id] = cells.duplicate()
	_ensure_seals()


## The grid is rebuilt from the chunk's own data after the chunk builds, which drops every dynamic
## blocker written before then. Re-asserting the seals each update is what keeps an unchosen route
## shut across that rebuild; the blocker write is a no-op once the cell already holds it.
func _ensure_seals() -> void:
	var gs = _get_game_state()
	if gs == null or gs.grid == null:
		return
	for route_id in _sealed_cells.keys():
		for cell in _sealed_cells[route_id]:
			gs.grid.add_dynamic_blocker(cell, "long_hall_mouth_%s" % str(route_id))


func _open_route(route_id: String) -> void:
	var gs = _get_game_state()
	if gs == null or gs.grid == null:
		return
	for cell in _sealed_cells.get(route_id, []):
		gs.grid.remove_dynamic_blocker(cell)
	_sealed_cells.erase(route_id)


func _on_board_read(_char_id: String = "") -> void:
	_show_message("Hall: %d HP, %.0f units. Long way: no HP, %.0f units." % [
		int(_hall_price.get("hp_cost", 0.0)), _hall_length, _safe_route_length()], 3.4)


## The long way is the same journey without the fee: it costs the minutes the hall was buying.
func _safe_route_length() -> float:
	return (_rejoin_x - MOUTH_X) + (HALL_Z - SAFE_Z) * 2.0


func _on_hall_taken(_char_id: String = "") -> void:
	if _committed_route != "":
		return
	_committed_route = "hall"
	_phase = "hall"
	_open_route("hall")
	_record_hp_at_commit()
	_wake_pursuer()
	_show_message("The hall wakes behind you. Run.", 2.4)
	_refresh_status()


func _on_safe_taken(_char_id: String = "") -> void:
	if _committed_route != "":
		return
	_committed_route = "safe"
	_phase = "safe"
	_open_route("safe")
	_record_hp_at_commit()
	_show_message("The long way. Nothing is chasing you.", 2.4)
	_refresh_status()


func _record_hp_at_commit() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	for member_id in PARTY_IDS:
		if gs.characters.has(member_id):
			_hp_at_commit[member_id] = float(gs.get_stat(member_id, "hp"))


## The chaser is placed exactly one lane lead behind the mouth at the moment of commitment, so the
## opening gap the model assumed and the gap the scene actually starts with are the same number.
func _wake_pursuer() -> void:
	var gs = _get_game_state()
	if gs == null or _pursuer != null:
		return
	var profile: Dictionary = _hall_price.get("profile", {})
	var lead := float(profile.get("pursuit_lead", 6.0))
	_pursuer = EnemyScript.new()
	_pursuer.name = "HallPursuer"
	_pursuer.display_name = "Ferrule"
	# One lane lead behind whoever is furthest back, measured from where the party actually stands at
	# the moment of commitment. Placing it off the mouth line instead would hand the chase a different
	# opening gap than the one the fee was computed from, and the lane would undercharge.
	var rear_x := MOUTH_X
	for member_id in PARTY_IDS:
		if gs.characters.has(member_id):
			rear_x = minf(rear_x, _get_character_position(member_id).x)
	_pursuer.position = Vector3(maxf(PLAZA_MIN_X + 0.5, rear_x - lead), 0.5, HALL_Z)
	_pursuer.move_speed = float(profile.get("pursuit_speed", 5.5))
	_pursuer.pursuit_speed = float(profile.get("pursuit_speed", 5.5))
	_pursuer.pursuit_direct = true
	# A corridor chase is a straight line, so the hop is long and the re-plan frequent: a chaser that
	# finishes a hop and then waits for its next update travels below its own speed, and the fee was
	# computed from the speed on the sheet.
	_pursuer.pursuit_hop = 9.0
	_pursuer.pursuit_update_interval = 0.2
	# Sight wide enough to hold the runner across the widest the sprint ever opens the gap. Anything
	# less and the chaser drops the chase mid-lane, and the lane collects nothing it advertised.
	_pursuer.detection_range = maxf(lead + 2.0,
		float(_hall_price.get("required_detection_range", 0.0)) + 2.0)
	_pursuer.attack_range = float(profile.get("attack_range", 3.0))
	_pursuer.charge_damage = float(profile.get("charge_damage", 25.0))
	_pursuer._detection_targets.assign(PARTY_IDS)
	add_child(_pursuer)
	_pursuer.char_id = PURSUER_ID
	_pursuer.game_state = gs
	gs.register_character(PURSUER_ID, _pursuer.position, _pursuer.move_speed,
		{"detection_range": float(_pursuer.detection_range)})
	if _pursuer.has_method("activate"):
		_pursuer.activate()


func _process(_delta: float) -> void:
	_update()


func headless_process(_delta: float) -> void:
	_update()


func _update() -> void:
	_ensure_seals()
	_apply_concealment()
	_check_progression()


## Concealment is positional and derived: the Capbage decides, per member, from where that body is.
func _apply_concealment() -> void:
	var gs = _get_game_state()
	if gs == null or _capbage == null or not is_instance_valid(_capbage):
		return
	for member_id in PARTY_IDS:
		if not gs.characters.has(member_id):
			continue
		var hidden := _capbage.conceals(_get_character_position(member_id))
		gs.set_character_concealment(member_id,
			GameState.CONCEAL_FULL if hidden else GameState.CONCEAL_NONE)


func _check_progression() -> void:
	if _phase != "hall":
		return
	var gs = _get_game_state()
	if gs == null or _capbage == null or not is_instance_valid(_capbage):
		return
	for member_id in PARTY_IDS:
		if gs.characters.has(member_id) \
				and _capbage.conceals(_get_character_position(member_id)):
			_phase = "hidden"
			_show_message("Cover. It loses you.", 2.2)
			_refresh_status()
			return


func _on_stat_changed(_char_id: String, stat_name: String, _value: float) -> void:
	if stat_name in ["hp", "stamina"]:
		_refresh_status()


func _on_exit(_char_id: String = "") -> void:
	_phase = "complete"
	_refresh_status()
	_show_message("Junction reached. The hall cost %d HP; the long way cost none." % [
		int(hp_paid())], 3.0)
	_set_preview_step("complete")


## What the route actually charged, summed across the party. This is the number the advertised fee is
## checked against, so an advertised price that the level does not charge shows up as a mismatch.
func hp_paid() -> float:
	var gs = _get_game_state()
	if gs == null:
		return 0.0
	var paid := 0.0
	for member_id in _hp_at_commit.keys():
		if gs.characters.has(member_id):
			paid += maxf(0.0,
				float(_hp_at_commit[member_id]) - float(gs.get_stat(str(member_id), "hp")))
	return paid


func advertised_hp_cost() -> float:
	return float(_hall_price.get("hp_cost", 0.0))


func hall_length() -> float:
	return _hall_length


func lane_price() -> Dictionary:
	return _hall_price.duplicate(true)


func committed_route() -> String:
	return _committed_route


func _refresh_status() -> void:
	if _status_label == null or not is_instance_valid(_status_label):
		return
	match _phase:
		"choosing":
			_status_label.text = "TWO WAYS ON\nHALL %d HP  ·  LONG WAY FREE" % [
				int(advertised_hp_cost())]
		"hall":
			_status_label.text = "THE HALL\nRUN"
		"safe":
			_status_label.text = "THE LONG WAY"
		"hidden":
			_status_label.text = "HIDDEN\nPAID %d HP" % int(hp_paid())
		"complete":
			_status_label.text = "JUNCTION"


func get_fragment_manifest() -> Dictionary:
	return {
		"components": [
			{"id": "route_board", "kind": "interactable", "node_name": "RouteBoard"},
			{"id": "hall_mouth", "kind": "interactable", "node_name": "HallMouth"},
			{"id": "safe_mouth", "kind": "interactable", "node_name": "SafeMouth"},
			{"id": "hall_exit", "kind": "interactable", "node_name": "HallExit"},
			{"id": "hide", "kind": "node", "node_class": "Capbage", "count": 1},
		],
		"behaviours": [
			{
				"id": "hall_geometry_is_the_arithmetic",
				"claim": "the built hall length is the length RiskLane tunes for its advertised fee",
				"test": "--test-long-hall-fee",
			},
			{
				"id": "hall_charges_what_it_advertises",
				"claim": "running the hall costs the party the HP the mouth quoted before commitment",
				"test": "--test-long-hall-fee",
			},
			{
				"id": "long_way_costs_no_hp",
				"claim": "the safe route reaches the same junction with nothing chasing and no HP paid",
				"test": "--test-long-hall-fee",
			},
			{
				"id": "a_route_cannot_be_entered_unpriced",
				"claim": "both mouths stay sealed until their fee has been chosen",
				"test": "--test-long-hall-fee",
			},
		],
	}


func get_grid_data() -> Dictionary:
	if _grid_width <= 0:
		if _hall_price.is_empty():
			configure_chunk({})
		_hide_x = MOUTH_X + float(_hall_price["lane_length"])
		_rejoin_x = _hide_x + 4.0
		_grid_width = int(ceilf(_rejoin_x)) + 5
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [0.0, 0.0, 0.0],
		"cell_size": 1.0,
		"width": _grid_width,
		"height": 10,
		"walkable_regions": [
			{"min": [PLAZA_MIN_X, 1.0], "max": [MOUTH_X, 9.0]},
			{"min": [MOUTH_X, 5.5], "max": [_rejoin_x + 2.0, 8.5]},
			{"min": [MOUTH_X, 0.5], "max": [_rejoin_x + 2.0, 3.5]},
			{"min": [_rejoin_x - 1.0, 0.5], "max": [_rejoin_x + 2.0, 8.5]},
		],
	}


func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate(true)


func get_preview_anchors() -> Dictionary:
	return {
		"route_board": Vector3(4.0, 0.0, 5.0),
		"hall_mouth": Vector3(MOUTH_X - 1.2, 0.0, HALL_Z),
		"safe_mouth": Vector3(MOUTH_X - 1.2, 0.0, SAFE_Z),
		"hide": Vector3(_hide_x, 0.0, HALL_Z),
		"junction": Vector3(_rejoin_x, 0.0, 5.0),
	}


func get_preview_state() -> Dictionary:
	return {
		"step": _phase,
		"route": _committed_route,
		"advertised_hp": advertised_hp_cost(),
		"hp_paid": hp_paid(),
		"hall_length": _hall_length,
	}


func reset_preview_state() -> void:
	_phase = "choosing"
	_committed_route = ""
	_hp_at_commit.clear()
	if _pursuer != null and is_instance_valid(_pursuer):
		var gs = _get_game_state()
		if gs != null and gs.characters.has(PURSUER_ID):
			gs.unregister_character(PURSUER_ID)
		_pursuer.queue_free()
	_pursuer = null
	_seal_route("hall", _hall_mouth_cells())
	_seal_route("safe", _safe_mouth_cells())
	_refresh_status()


func get_preview_camera_profile() -> Dictionary:
	return {
		"follow_offset": Vector3(0.0, 26.0, 16.0),
		"min_zoom": 0.5,
		"max_zoom": 2.2,
		"initial_zoom": 1.2,
		"reset_yaw": true,
	}
