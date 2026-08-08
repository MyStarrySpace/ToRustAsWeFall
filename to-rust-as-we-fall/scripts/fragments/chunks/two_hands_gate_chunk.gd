extends "res://scripts/scene_chunks/scene_chunk.gd"

## TWO HANDS ON THE GATE — the bare-pair held-station co-op (FRAGMENT_IDEAS.md #6).
##
## One tension, one verb: HOLD. The crossing pads are dead metal unless somebody is standing on a
## gate console, and the console cannot be held by the person crossing — so the pair must split the
## job and then TRADE it. Aster holds the near console while Peris crosses; Peris then holds the FAR
## console so Aster can follow. The role is inheritable (P12), which is the whole point.
##
## Everything here COMPOSES shipped systems; no new mechanism:
##   - the held console is the wash relay's plate rule (derive "held" from canonical GameState
##     positions each sample, ignore downed / externally-traversing bodies -- derived, never logged)
##   - the crossing is a PortalPad pair, gated through its own `set_pre_trigger_validator` seam, so a
##     refused crossing is a real player-facing refusal rather than an invisible no-op
##   - the pressure is a Naturalizer walking an authored patrol straight over the near console, so
##     HOLDING is what exposes you. The far console is unwatched: crossing is its own reward.
##
## The near console is the only watched one, so the first hold is the expensive one and the second is
## safe. That asymmetry is what makes trading the role feel like progress rather than repetition.

const NEAR_CONSOLE := Vector3(5.5, 0.0, 6.5)
const FAR_CONSOLE := Vector3(20.5, 0.0, 6.5)
const NEAR_PAD := Vector3(10.5, 0.0, 6.5)
const FAR_PAD := Vector3(15.5, 0.0, 6.5)
const EXIT_POS := Vector3(24.5, 0.0, 6.5)

## Matches the wash relay's plate reach so "standing on it" reads the same everywhere.
const HOLD_RADIUS := 1.4

const IDLE_LAMP_ENERGY := 0.55   # the station is findable at rest
const HELD_LAMP_ENERGY := 2.4    # and unmistakable while borne

const PARTY_IDS := ["aster", "peris"]

## The pair starts on the south lip of the near deck, OUTSIDE the sentry's reach at the near end of
## its route. Spawning inside that reach meant the patrol opened in pursuit and the fragment was
## unwinnable before the player touched anything -- the encounter has to begin with a readable sweep.
const SPAWNS := {
	"aster": Vector3(2.5, 0.0, 1.5),
	"peris": Vector3(3.6, 0.0, 1.5),
}

var _phase := "ready"                # ready | crossed | complete
var _held := {"near": false, "far": false}
var _holders := {}                   # console key -> character id currently holding it
var _near_pad
var _far_pad
var _status_label: Label3D
var _near_light: OmniLight3D
var _far_light: OmniLight3D
var _sentry
var _crossings := 0

func _build_chunk() -> void:
	_add_floor(self, Vector3(6.0, -0.05, 6.5), Vector3(11.0, 0.1, 12.0), Color(0.10, 0.12, 0.14))
	_add_floor(self, Vector3(20.5, -0.05, 6.5), Vector3(11.0, 0.1, 12.0), Color(0.10, 0.12, 0.14))
	# The gap between the decks is the reason the pads exist; it is never walkable. It is a CHASM, not
	# a wall: a 1.8 m slab here threw the low afternoon sun's shadow across the entire far deck and
	# hid the far console, which is half the puzzle. Knee-high lips mark each edge instead -- the drop
	# reads as uncrossable without shadowing what the player needs to see.
	_add_box(self, Vector3(11.3, 0.2, 6.5), Vector3(0.35, 0.4, 12.0), Color(0.20, 0.16, 0.13))
	_add_box(self, Vector3(14.7, 0.2, 6.5), Vector3(0.35, 0.4, 12.0), Color(0.20, 0.16, 0.13))

	_add_console(NEAR_CONSOLE, "NEAR GATE", true)
	_add_console(FAR_CONSOLE, "FAR GATE", false)

	_near_pad = _add_crossing_pad("NearCrossing", NEAR_PAD, FAR_PAD)
	_far_pad = _add_crossing_pad("FarCrossing", FAR_PAD, NEAR_PAD)

	_add_interactable(
		self, "GateExit", "Leave through the far door", EXIT_POS, "LEAVE", "", 0.6, true
	).interacted.connect(_on_exit)

	_status_label = _add_label(self, "", Vector3(13.0, 3.4, 6.5), Color(0.72, 0.84, 0.96))
	_spawn_sentry()

## A console is a visible plate plus a lamp that reports whether it is currently bearing someone.
## No interactable: standing on it IS the verb, so there is nothing to click and nothing to explain.
func _add_console(pos: Vector3, label: String, watched: bool) -> void:
	# Warm for the watched console, cool for the safe one -- the two sides of the trade read apart.
	var tint := Color(0.42, 0.30, 0.22) if watched else Color(0.34, 0.62, 0.55)
	# The plate EMITS so it reads as a station the moment it is visible, without depending on how
	# much room light reaches it. (It does NOT make the far plate visible early: the far deck is
	# hidden by the vision mask until a member stands there -- measured, the far console jumps from
	# (25,29,39) to (109,198,160) the instant one does. That masking is correct and is not something
	# a chunk should fight.) The lamp stays free to spike as the HOLD tell.
	_add_box(self, pos + Vector3(0.0, 0.06, 0.0), Vector3(2.4, 0.12, 2.4), tint, tint, 0.9)
	_add_label(self, label, pos + Vector3(0.0, 1.9, 0.0),
		Color(0.95, 0.72, 0.46) if watched else Color(0.62, 0.88, 0.78))
	var lamp := OmniLight3D.new()
	lamp.name = "%sLamp" % label.replace(" ", "")
	lamp.position = pos + Vector3(0.0, 1.2, 0.0)
	lamp.omni_range = 4.0
	# Idle glow, not off: a console reads as equipment at rest and BRIGHTENS when borne, so the
	# energy step is the hold tell rather than the only thing that makes the station findable.
	lamp.light_energy = IDLE_LAMP_ENERGY
	lamp.light_color = Color(0.55, 0.95, 0.70)
	add_child(lamp)
	if watched:
		_near_light = lamp
	else:
		_far_light = lamp

func _add_crossing_pad(pad_name: String, source: Vector3, destination: Vector3):
	var pad = PortalPad.new()
	pad.name = pad_name
	pad.configure_data(_get_game_state(), source, destination, 1.2)
	add_child(pad)
	if pad.has_method("set_pre_trigger_validator"):
		pad.set_pre_trigger_validator(_validate_crossing)
	return pad

## A Naturalizer walking the near deck, straight over the watched console. Patrol is authored (not
## roam) because the whole puzzle is timing ITS sweep -- the window has to be readable, not wandering.
func _spawn_sentry() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	var enemy := (Naturalizer.new() as Enemy)
	enemy.name = "GateSentry"
	enemy.position = Vector3(5.5, 0.0, 5.0)
	enemy.move_speed = 1.9
	enemy.detection_range = 3.4
	enemy._detection_targets.assign(PARTY_IDS)
	add_child(enemy)
	enemy.char_id = "gate_sentry"
	enemy.game_state = gs
	if not gs.characters.has("gate_sentry"):
		gs.register_character("gate_sentry", enemy.position, enemy.move_speed,
			{"detection_range": float(enemy.detection_range)})
	if enemy.has_method("activate"):
		enemy.activate()
	if enemy.has_method("set_patrol"):
		# The route sweeps the watched console (z 6.5) but stops short of the spawn lip, so the
		# opening frame shows the threat WALKING rather than already on top of you.
		var route: Array[Vector3] = [
			Vector3(5.5, 0.0, 5.0),
			Vector3(5.5, 0.0, 11.5),
		]
		enemy.set_patrol(route)
	_sentry = enemy

## The whole read is "two decks, one gap, a console on each side". The default preview camera follows
## the active character from close in, which opens on the spawn corner and shows one deck -- the
## player cannot see the problem they are being asked to solve. Pull back and sit over the gap so the
## opening frame carries the composition; the player can still zoom in once they know the shape.
func get_preview_camera_profile() -> Dictionary:
	return {
		"follow_offset": Vector3(0.0, 21.0, 15.0),
		"min_zoom": 0.5,
		"max_zoom": 2.0,
		"initial_zoom": 1.0,
		"reset_yaw": true,
	}

## Home reframes the PUZZLE (the gap between the decks), not whoever happens to be selected.
func get_preview_camera_recenter_target() -> Vector3:
	return Vector3(13.0, 0.0, 6.5)

func configure_chunk(_config: Dictionary) -> void:
	pass

## The crossing seam. A pad only carries somebody while a DIFFERENT body bears a console: you cannot
## open your own gate. Returning false here produces the ordinary refusal presentation, so the player
## is told why rather than clicking a pad that silently does nothing.
func _validate_crossing(_source, character_id: String) -> bool:
	_refresh_holds()
	for key in _holders.keys():
		if str(_holders[key]) != character_id:
			return true
	return false

## Derived per sample from canonical positions, exactly like the wash relay's plates: never logged,
## so a replay rebuilds it from the movements alone.
func _refresh_holds() -> void:
	var gs = _get_game_state()
	_holders.clear()
	_held["near"] = false
	_held["far"] = false
	if gs == null:
		return
	for entry in [["near", NEAR_CONSOLE], ["far", FAR_CONSOLE]]:
		var key := str(entry[0])
		var pad: Vector3 = entry[1]
		for char_id in PARTY_IDS:
			if not gs.characters.has(char_id) or gs.is_downed(char_id) \
					or gs.is_external_traversal_active(char_id):
				continue
			var p: Vector3 = gs.get_position(char_id)
			if absf(p.x - pad.x) <= HOLD_RADIUS and absf(p.z - pad.z) <= HOLD_RADIUS:
				_held[key] = true
				_holders[key] = char_id
				break

func _members_on_far_deck() -> int:
	var gs = _get_game_state()
	if gs == null:
		return 0
	var count := 0
	for char_id in PARTY_IDS:
		if gs.characters.has(char_id) and gs.get_position(char_id).x > 13.0:
			count += 1
	return count

func _on_exit() -> void:
	if _phase == "complete":
		return
	if _members_on_far_deck() < PARTY_IDS.size():
		return
	_phase = "complete"

func reset_preview_state() -> void:
	_phase = "ready"
	_crossings = 0
	_holders.clear()
	_held["near"] = false
	_held["far"] = false

func headless_process(delta: float) -> void:
	_tick(delta)

func _process(delta: float) -> void:
	_tick(delta)

func _tick(_delta: float) -> void:
	_refresh_holds()
	if _phase == "ready" and _members_on_far_deck() > 0:
		_phase = "crossed"
	if _near_light != null:
		_near_light.light_energy = HELD_LAMP_ENERGY if bool(_held["near"]) else IDLE_LAMP_ENERGY
	if _far_light != null:
		_far_light.light_energy = HELD_LAMP_ENERGY if bool(_held["far"]) else IDLE_LAMP_ENERGY
	if _status_label != null:
		var bearing: Array[String] = []
		for key in ["near", "far"]:
			if bool(_held[key]):
				bearing.append("%s: %s" % [key.to_upper(), str(_holders.get(key, "")).to_upper()])
		_status_label.text = "GATE %s  //  %s" % [
			"OPEN" if not bearing.is_empty() else "DEAD",
			" | ".join(bearing) if not bearing.is_empty() else "NOBODY ON A CONSOLE",
		]

func get_grid_data() -> Dictionary:
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [0.0, 0.0, 0.0],
		"cell_size": 1.0,
		"width": 27,
		"height": 14,
		"walkable_regions": [
			{"min": [1.0, 1.0], "max": [11.4, 12.4]},
			{"min": [15.0, 1.0], "max": [25.9, 12.4]},
		],
	}

func get_scene_title() -> String:
	return "Two Hands on the Gate"

func get_scene_help() -> String:
	return "The crossing pads are dead unless somebody stands on a gate console, and the one crossing cannot be the one holding. Hold the near console so your partner can cross, then let them take the far console and follow. A Naturalizer walks the near console; only that side is watched."

func get_default_character() -> String:
	return "aster"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate()

func get_preview_anchors() -> Dictionary:
	return {
		"near_console": NEAR_CONSOLE,
		"far_console": FAR_CONSOLE,
		"near_pad": NEAR_PAD,
		"far_pad": FAR_PAD,
		"gate_exit": EXIT_POS,
	}

func get_preview_state() -> Dictionary:
	_refresh_holds()
	return {
		"contract_id": "two_hands_gate_v1",
		"phase": _phase,
		"held": _held.duplicate(),
		"holders": _holders.duplicate(),
		"on_far_deck": _members_on_far_deck(),
		"crossings": _crossings,
	}
