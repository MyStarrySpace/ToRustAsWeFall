extends "res://scripts/scene_chunks/scene_chunk.gd"

## The CHANNELS WASH-INTRO — the diegetic teacher at Endo's Junction, before the fall to the spiral
## (CHANNELS_DESIGN.md "Entry teaching"). One self-contained room teaches the whole channels stealth+wash
## vocabulary before any of it can kill the player:
##   - THE WASH: three adjacent channels phased so AT LEAST ONE is always flooding — you can't walk across.
##   - THE FLURE: lure flower; activating it pulls the enemies toward it (its attract range is LARGER than the
##     enemies' player-sense range, so they go for the flure, not you — "they don't immediately come across").
##   - WASH KILLS ENEMIES: the lured enemies cross the channels to reach the flure and DROWN (the drain-loop
##     drown, planted here first as the lesson).
##   - CAPBAGE (tight hide, GDD 7.9): self-sealing leaf head; a member inside is fully undetectable.
##   - PORTAL: a free teleport across the channels. The enemies guard the far exit, so crossing WITHOUT
##     clearing them first gets you killed — flure them into the wash, THEN portal across.
## Flat room (no helix warp — this is the antechamber). All timing rides the scheduler (replay/FF-safe);
## per-frame work is cosmetic toggles + positional checks.

const EnemyScript := preload("res://scripts/game/ai/enemy.gd")
const WaterShader := preload("res://resources/channels_water.gdshader")

const WORLD_SLOT := {
	"slot_id": "act1_channels_wash_intro",
	"act": 1,
	"region": "Channels / Endo's Junction (wash intro)",
	"entry_shelter_id": "endo_junction",
	"exit_shelter_id": "channels_spiral_top",
	"canonical_party": ["aster", "peris", "endo"],
	"preview_party_preset": "full_party_full_health",
	"next_slot": "act1_channels_first_spiral",
}

const PARTY_IDS := ["aster", "peris", "endo"]

# --- Layout (flat: x = across the room toward the spiral, z = lane) ---
const FLOOR_CENTER := Vector3(14.0, -0.05, 0.0)
const FLOOR_SIZE := Vector3(34.0, 0.1, 14.0)
const Z_HALF := 5.0

const SPAWNS := {
	"aster": Vector3(3.4, 0.5, 1.4),
	"peris": Vector3(2.2, 0.5, 0.0),
	"endo": Vector3(2.8, 0.5, -1.6),
}

const FLURE_POS := Vector3(6.0, 0.5, 0.0)        # near bank — the player reaches + lights it
const CAPBAGE_POS := [Vector3(2.0, 0.5, 3.6), Vector3(4.0, 0.5, -3.6), Vector3(7.5, 0.5, 3.4)]
const CAPBAGE_RADIUS := 1.4                       # inside this of an open Capbage = fully concealed (tight hide)

# Three adjacent channels spanning the room's z-width, between the near bank and the far bank.
const CHANNEL_X := [11.0, 13.5, 16.0]             # centre x of each channel strip
const CHANNEL_HALF := 1.25                        # each strip's half-width in x
const CHANNEL_PERIOD := 3.0
const CHANNEL_DUR := 1.6                          # flood on-time; with 3 strips phased 0/1/2 over a 3s period
const CHANNEL_PHASE := [0.0, 1.0, 2.0]            # => at every instant at least one strip is flooding

const PORTAL_IN_POS := Vector3(8.0, 0.5, -2.0)    # near-bank portal — activatable, bidirectional
const PORTAL_OUT_POS := Vector3(21.0, 0.5, -2.0)  # far-bank portal
const PORTAL_RADIUS := 1.2

const WASH_BACK_POS := Vector3(2.0, 0.5, 0.0)     # a player flushed by a channel is swept back here (section start)

const FAR_BANK_X := 19.5
const EXIT_POS := Vector3(27.0, 0.5, 0.0)         # reach here -> complete (-> the spiral)
const EXIT_RADIUS := 2.2

const ENEMY_SPECS := [
	{"id": "wash_intro_guard_0", "pos": Vector3(23.0, 0.5, 2.4)},
	{"id": "wash_intro_guard_1", "pos": Vector3(24.5, 0.5, -2.0)},
]
const ENEMY_SPEED := 2.4
const ENEMY_DETECT := 4.0                          # PLAYER-sense range (small): they don't notice you across the room
const FLURE_ATTRACT := 32.0                        # FLURE-sense range (large): activating it grabs them room-wide

var _phase := "ready"
var _flooding := [false, false, false]
var _channel_water := []                           # per channel: the flood mesh
var _flure_active := false
var _flure_mesh: MeshInstance3D
var _flure_mat: StandardMaterial3D
var _enemies := []
var _drowned := 0
var _drowned_ids := {}                             # char_id -> true: dedupe the drown (once per hunter, one line)
var _washed_back := 0                              # how many times a party member was flushed by a channel
var _portal_near                                   # the two portal interactables (activatable, bidirectional)
var _portal_far
var _scheduled := false
var _last_outcome := ""

func _build_chunk() -> void:
	# A readable floor + walls (the bare graybox rendered black for want of light — these are lit, plus the
	# lights below). Endo's junction: damp stone-grey deck, darker channel-iron walls.
	_add_floor(self, FLOOR_CENTER, FLOOR_SIZE, Color(0.34, 0.36, 0.40))
	_add_box(self, Vector3(FLOOR_CENTER.x, 2.0, -Z_HALF - 0.2), Vector3(FLOOR_SIZE.x, 4.0, 0.4), Color(0.24, 0.25, 0.28))
	_add_box(self, Vector3(FLOOR_CENTER.x, 2.0, Z_HALF + 0.2), Vector3(FLOOR_SIZE.x, 4.0, 0.4), Color(0.24, 0.25, 0.28))
	# Lights so the room READS (the chunk geometry isn't lit by the preview environment alone).
	for lx in [3.0, 11.0, 19.0, 27.0]:
		_add_light(self, Vector3(lx, 4.2, 0.0), Color(0.62, 0.68, 0.78), 2.4, 16.0)
	_add_label(self, "TO SPIRAL", EXIT_POS + Vector3(0.0, 2.0, 0.0), Color(0.5, 0.8, 0.9))
	_add_marker(EXIT_POS, Vector3(EXIT_RADIUS * 1.6, 0.4, EXIT_RADIUS * 1.6), Color(0.3, 0.7, 0.55), 1.4, "")

	# Three channels (flood strips). Built under a Node3D root so they survive a future hide pass; flat here.
	_channel_water = []
	for i in range(CHANNEL_X.size()):
		var cx: float = CHANNEL_X[i]
		var bed := _add_box(self, Vector3(cx, -0.16, 0.0), Vector3(CHANNEL_HALF * 2.0, 0.18, Z_HALF * 2.0), Color(0.05, 0.07, 0.09))
		bed.name = "ChannelBed%d" % i
		var water := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(CHANNEL_HALF * 2.0, 0.34, Z_HALF * 2.0); water.mesh = bm
		var wmat := ShaderMaterial.new(); wmat.shader = WaterShader; wmat.render_priority = 127
		water.material_override = wmat
		water.position = Vector3(cx, 0.12, 0.0)
		water.visible = false
		add_child(water)
		_channel_water.append(water)
		_add_label(self, "Channel %d" % (i + 1), Vector3(cx, 1.4, 0.0), Color(0.4, 0.75, 0.85))

	# Capbage tight hides (×3) on the near bank.
	for j in range(CAPBAGE_POS.size()):
		_build_capbage(CAPBAGE_POS[j], j)

	# The flure (near bank) — an INSPECTION interactable: click -> walk -> light it on arrival.
	var flure := _add_interactable(self, "Flure", "Light the flure", FLURE_POS, "FLURE", "", 1.2, true, 1.6,
		Interactable.InteractableType.INSPECTION, false)
	_flure_mesh = _add_object_glow(flure, Vector3(0.0, 0.35, 0.0), 0.45, Color(0.95, 0.78, 0.2), 0.5)
	_flure_mat = _flure_mesh.material_override as StandardMaterial3D
	_outline_interactable_child(flure, _flure_mesh, "Flure", 1.4)
	flure.interacted.connect(func() -> void: activate_flure())

	# Portal — an ACTIVATABLE pair (not an area). Click one, the active member walks to it and steps through;
	# only that one member crosses (whoever arrives first), and it's bidirectional + reusable so they can return.
	_portal_near = _add_interactable(self, "PortalNear", "Step through", PORTAL_IN_POS, "PORTAL", "", 0.6, false, PORTAL_RADIUS,
		Interactable.InteractableType.INSPECTION, false)
	var pn := _add_object_glow(_portal_near, Vector3(0.0, 0.6, 0.0), 0.5, Color(0.55, 0.42, 0.98), 0.8)
	_outline_interactable_child(_portal_near, pn, "PortalNear", 1.4)
	_add_label(self, "PORTAL", PORTAL_IN_POS + Vector3(0.0, 1.6, 0.0), Color(0.6, 0.5, 1.0))
	_portal_near.interacted.connect(func() -> void: _teleport_via_portal(true))
	_portal_far = _add_interactable(self, "PortalFar", "Step through", PORTAL_OUT_POS, "PORTAL", "", 0.6, false, PORTAL_RADIUS,
		Interactable.InteractableType.INSPECTION, false)
	var pf := _add_object_glow(_portal_far, Vector3(0.0, 0.6, 0.0), 0.5, Color(0.55, 0.42, 0.98), 0.8)
	_outline_interactable_child(_portal_far, pf, "PortalFar", 1.4)
	_portal_far.interacted.connect(func() -> void: _teleport_via_portal(false))

	_spawn_enemies()
	reset_preview_state()
	_set_preview_step("channels_wash_intro_start")

func _build_capbage(pos: Vector3, j: int) -> void:
	# A tight-hide leaf head (cosmetic dome) the player tucks into; concealment is positional (CONCEAL_FULL).
	var head := _add_box(self, pos + Vector3(0.0, 0.2, 0.0), Vector3(1.5, 1.0, 1.5), Color(0.16, 0.34, 0.18),
		Color(0.3, 0.7, 0.35), 0.25, "Capbage%d" % j)
	_add_label(self, "CAPBAGE", pos + Vector3(0.0, 1.5, 0.0), Color(0.5, 0.85, 0.55))

func _add_marker(pos: Vector3, size: Vector3, color: Color, energy: float, label: String) -> void:
	var mesh := _add_box(self, pos - Vector3(0.0, 0.18, 0.0), size, color * 0.4, color, energy)
	if label != "":
		_add_label(self, label, pos + Vector3(0.0, 1.4, 0.0), color)

func _add_object_glow(parent: Node3D, offset: Vector3, radius: float, color: Color, energy: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new(); sph.radius = radius; sph.height = radius * 2.0; mi.mesh = sph
	mi.material_override = _make_material(color * 0.5, color, energy)
	mi.position = offset
	parent.add_child(mi)
	return mi

func _spawn_enemies() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	for spec in ENEMY_SPECS:
		var enemy := EnemyScript.new()
		enemy.name = "WashIntro_%s" % str(spec["id"])
		enemy.position = spec["pos"]
		enemy.move_speed = ENEMY_SPEED
		enemy.detection_range = ENEMY_DETECT
		enemy._detection_targets.assign(PARTY_IDS)
		add_child(enemy)
		enemy.char_id = str(spec["id"])
		enemy.game_state = gs
		gs.register_character(str(spec["id"]), enemy.position, ENEMY_SPEED, {"detection_range": ENEMY_DETECT})
		if enemy.has_method("activate"):
			enemy.activate()
		# Guard the far bank by the exit (idle hold; they only pathfind to chase the player or chase the flure).
		_enemies.append(enemy)

func _process(delta: float) -> void:
	_update(delta)

func headless_process(delta: float) -> void:
	_update(delta)

# --- Flood cadence (scheduler-driven; replay + fast-forward invariant) ---

func _ensure_scheduled() -> void:
	if _scheduled:
		return
	var sched = _get_scheduler()
	if sched == null:
		return
	_scheduled = true
	for i in range(CHANNEL_X.size()):
		sched.schedule_after(CHANNEL_PHASE[i] + 0.01, _make_onset(i), "wi_onset_%d" % i)

func _make_onset(i: int) -> Callable:
	return func() -> void: _channel_onset(i)

func _channel_onset(i: int) -> void:
	if _phase in ["complete", "failed"]:
		return
	_flooding[i] = true
	if i < _channel_water.size() and is_instance_valid(_channel_water[i]):
		_channel_water[i].visible = true
	var sched = _get_scheduler()
	if sched != null:
		sched.schedule_after(CHANNEL_DUR, func() -> void: _channel_off(i), "wi_off_%d" % i)
		sched.schedule_after(CHANNEL_PERIOD, _make_onset(i), "wi_onset_%d" % i)

func _channel_off(i: int) -> void:
	_flooding[i] = false
	if i < _channel_water.size() and is_instance_valid(_channel_water[i]):
		_channel_water[i].visible = false

func _channel_index_at(x: float) -> int:
	for i in range(CHANNEL_X.size()):
		if abs(x - CHANNEL_X[i]) <= CHANNEL_HALF:
			return i
	return -1

# --- Per-frame state ---

func _update(_delta: float) -> void:
	if _phase == "ready":
		_phase = "active"
	if _phase in ["complete", "failed"]:
		return
	_ensure_scheduled()
	var gs = _get_game_state()
	if gs == null:
		return

	# Capbage concealment: a party member inside an open Capbage is fully undetectable (tight hide).
	for cid in PARTY_IDS:
		if not gs.characters.has(cid):
			continue
		var p := _get_character_position(cid)
		var hidden := false
		for cpos in CAPBAGE_POS:
			if Vector2(p.x - cpos.x, p.z - cpos.z).length() <= CAPBAGE_RADIUS:
				hidden = true
				break
		gs.set_character_concealment(cid, GameState.CONCEAL_FULL if hidden else GameState.CONCEAL_NONE)

	# Drown: an enemy caught in a flooding channel strip is swept off (the wash kills it).
	for enemy in _enemies:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		var ex: float = gs.get_position(enemy.char_id).x if gs.characters.has(enemy.char_id) else enemy.position.x
		var ci := _channel_index_at(ex)
		if ci >= 0 and _flooding[ci]:
			_drown_enemy(enemy)

	# The wash flushes PLAYERS too: a member standing in a flooding channel is swept back to the section start
	# (for now the left bank; eventually a spot near Endo's junction). Snapping them out clears the footprint, so
	# it can't re-fire every frame. The portal is the safe way across — the channels themselves are lethal.
	for cid in PARTY_IDS:
		if not gs.characters.has(cid):
			continue
		var mp := _get_character_position(cid)
		var mci := _channel_index_at(mp.x)
		if mci >= 0 and _flooding[mci] and abs(mp.z) <= Z_HALF:
			gs.command_stop(cid)
			_set_character_position(cid, WASH_BACK_POS)
			_washed_back += 1
			_say("// WASH // the current takes you back")

	# Win: any member reaches the far exit (via the portal) -> the wash intro is cleared.
	for cid in PARTY_IDS:
		if gs.characters.has(cid):
			var fp := _get_character_position(cid)
			if Vector2(fp.x - EXIT_POS.x, fp.z - EXIT_POS.z).length() <= EXIT_RADIUS:
				_complete()
				return

func _drown_enemy(enemy) -> void:
	if not is_instance_valid(enemy) or not enemy.is_alive():
		return
	# Dedupe: take_damage doesn't necessarily flip is_alive() the same frame, and the body can sit in the
	# flooding strip for a tick or two — so without this guard the drown counted (and announced) twice.
	if _drowned_ids.has(enemy.char_id):
		return
	_drowned_ids[enemy.char_id] = true
	if enemy.has_method("take_damage"):
		enemy.take_damage(enemy.max_hp)   # die() doesn't zero hp; full damage downs it cleanly
	_drowned += 1
	var gs = _get_game_state()
	if gs != null and gs.characters.has(enemy.char_id):
		gs.set_character_distracted(enemy.char_id, false)
	_say("// WASH // the channel takes the one drawn into it")

# --- Flure (the lure) ---

## Activate the flure: it EMITS A SIGNAL the hunters home in on. Every hunter within the flure's (large) signal
## range drops the hunt and moves to it, crossing the channels to reach it — and drowning. The signal range is
## bigger than the hunters' player-sense range, so they lock onto the flure rather than the party (they don't
## immediately come across at you).
func activate_flure() -> bool:
	if _phase in ["complete", "failed"]:
		return false
	_flure_active = true
	if _flure_mat != null:
		_flure_mat.emission_energy_multiplier = 3.0
	var gs = _get_game_state()
	if gs == null:
		return false
	var pulled := 0
	for enemy in _enemies:
		if not is_instance_valid(enemy) or not enemy.is_alive() or not gs.characters.has(enemy.char_id):
			continue
		if gs.get_position(enemy.char_id).distance_to(FLURE_POS) <= FLURE_ATTRACT:
			gs.set_character_distracted(enemy.char_id, true)   # it stops noticing the party at range
			gs.command_move_to_pos(enemy.char_id, FLURE_POS)    # and tracks the signal — across the channels
			pulled += 1
	_last_outcome = "flure_lit"
	_set_preview_step("channels_wash_intro_flure")
	_say("// FLURE // signal up — the hunters lock onto it")
	return pulled > 0

## Step a SINGLE member through the portal — the one who activated it (whoever arrived first). Bidirectional
## (near <-> far) and reusable, so a member can return. Never teleports the whole party at once.
func _teleport_via_portal(to_far: bool) -> void:
	if _phase in ["complete", "failed"]:
		return
	var src = _portal_near if to_far else _portal_far
	var dest: Vector3 = PORTAL_OUT_POS if to_far else PORTAL_IN_POS
	var who := ""
	if src != null and ("active_character" in src):
		who = str(src.active_character)
	if who == "":
		who = _get_active_character()
	var gs = _get_game_state()
	if gs == null or who == "" or not gs.characters.has(who):
		return
	gs.command_stop(who)
	_set_character_position(who, dest)
	_say("// PORTAL // through")

func _complete() -> void:
	if _phase == "complete":
		return
	_phase = "complete"
	_last_outcome = "complete"
	_set_preview_step("channels_wash_intro_complete")
	_say("Across. The spiral's below us now.", "ASTER")

# --- Scene chunk interface ---

func get_scene_title() -> String:
	return "Channels — Wash Intro"

func get_scene_help() -> String:
	return "The hunters guard the way down. Light the flure to draw them into the channels — the wash takes them — then step through the portal across. Tuck into a Capbage if one gets close."

func get_default_character() -> String:
	return "endo"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate(true)

## A flat room grid so movement, the hover grid, and the path preview snap to cells (the gridless fallback
## drew the hover patch off the deck). The WHOLE room is walkable — the channels are hazards, not walls, so
## both the party and the lured hunters path THROUGH them (and get washed); the wash is the gate, not the grid.
func get_grid_data() -> Dictionary:
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [-3.0, 0.0, -7.0],
		"cell_size": 1.0,
		"width": 34,
		"height": 14,
		"walkable_regions": [
			{"min": [-2.0, -5.0], "max": [30.0, 5.0]},
		],
	}

func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors.merge({
		"flure": FLURE_POS, "portal_in": PORTAL_IN_POS, "portal_out": PORTAL_OUT_POS,
		"exit": EXIT_POS, "capbage_0": CAPBAGE_POS[0], "capbage_1": CAPBAGE_POS[1], "capbage_2": CAPBAGE_POS[2],
	}, true)
	return anchors

func get_preview_time_state() -> Dictionary:
	return {"day": 2, "time": 0.6, "routing_mode": "safe",
		"note_default": "Endo's junction. The hunters guard the drop to the spiral — read the channels, use the flure."}

func get_preview_abilities() -> Array:
	return []

func reset_preview_state() -> void:
	_phase = "ready"
	_flooding = [false, false, false]
	_flure_active = false
	_drowned = 0
	_drowned_ids = {}
	_washed_back = 0
	_scheduled = false
	_last_outcome = ""
	if _flure_mat != null:
		_flure_mat.emission_energy_multiplier = 0.5
	for w in _channel_water:
		if is_instance_valid(w):
			w.visible = false
	var sched = _get_scheduler()
	if sched != null:
		for i in range(CHANNEL_X.size()):
			sched.cancel_tag("wi_onset_%d" % i); sched.cancel_tag("wi_off_%d" % i)
	_set_preview_step("channels_wash_intro_start")

func get_preview_state() -> Dictionary:
	var any_flooding := false
	for f in _flooding:
		if f:
			any_flooding = true
			break
	var enemies_alive := 0
	for enemy in _enemies:
		if is_instance_valid(enemy) and enemy.is_alive():
			enemies_alive += 1
	return {
		"phase": _phase,
		"complete": _phase == "complete",
		"flure_active": _flure_active,
		"any_channel_flooding": any_flooding,
		"flooding": _flooding.duplicate(),
		"drowned": _drowned,
		"enemies_alive": enemies_alive,
		"flure_attract_range": FLURE_ATTRACT,
		"player_sense_range": ENEMY_DETECT,
		"last_outcome": _last_outcome,
	}
