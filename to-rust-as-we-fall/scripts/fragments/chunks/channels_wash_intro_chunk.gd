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

# Every placement sits on a grid CELL CENTRE (grid origin -3/-7, cell 1.0 => centres land on integer+0.5).
# Movement, the hover grid, and the position preview all snap to those cells, so off-centre props made the
# first preview segment jump sideways onto the nearest cell. Authoring on-centre keeps objects + routes aligned.
const SPAWNS := {
	"aster": Vector3(3.5, 0.5, 1.5),
	"peris": Vector3(2.5, 0.5, 0.5),
	"endo": Vector3(2.5, 0.5, -1.5),
}

const FLURE_POS := Vector3(6.5, 0.5, 0.5)        # near bank — the player reaches + lights it
const CAPBAGE_POS := [Vector3(2.5, 0.5, 3.5), Vector3(4.5, 0.5, -3.5), Vector3(7.5, 0.5, 3.5)]
const CAPBAGE_RADIUS := 1.4                       # inside this of an open Capbage = fully concealed (tight hide)

# Three adjacent channels spanning the room's z-width, between the near bank and the far bank.
const CHANNEL_X := [11.0, 13.5, 16.0]             # centre x of each channel strip
const CHANNEL_HALF := 1.25                        # each strip's half-width in x
const CHANNEL_PERIOD := 3.0
const CHANNEL_DUR := 1.6                          # flood on-time; with 3 strips phased 0/1/2 over a 3s period
const CHANNEL_PHASE := [0.0, 1.0, 2.0]            # => at every instant at least one strip is flooding

const PORTAL_IN_POS := Vector3(8.5, 0.5, -1.5)    # near-bank portal — activatable, bidirectional
const PORTAL_OUT_POS := Vector3(21.5, 0.5, -1.5)  # far-bank portal
const PORTAL_RADIUS := 1.2

const WASH_BACK_POS := Vector3(2.5, 0.5, 0.5)     # a player flushed by a channel is swept back here (section start)

const FAR_BANK_X := 19.5
const EXIT_POS := Vector3(27.5, 0.5, 0.5)         # reach here -> complete (-> the spiral)
const EXIT_RADIUS := 2.2

const ENEMY_SPECS := [
	{"id": "wash_intro_guard_0", "pos": Vector3(23.5, 0.5, 2.5)},
	{"id": "wash_intro_guard_1", "pos": Vector3(24.5, 0.5, -1.5)},
]
const ENEMY_SPEED := 2.4
const ENEMY_DETECT := 4.0                          # PLAYER-sense range (small): they don't notice you across the room
const FLURE_ATTRACT := 32.0                        # FLURE-sense range (large): activating it grabs them room-wide

var _phase := "ready"
var _channels: Array = []                          # the Channel hazard objects (own their visual + flood cadence)
var _flure: Flure                                  # the lure flower — a self-contained gameplay object (Flure class)
var _capbages: Array = []                          # the Capbage hide objects (own their visual/outline/hide radius)
var _enemies := []
var _drowned := 0
var _drowned_ids := {}                             # char_id -> true: dedupe the drown (once per hunter, one line)
var _washed_back := 0                              # how many times a party member was flushed by a channel
var _portal_near: PortalPad                        # the two portal pads (activatable, bidirectional)
var _portal_far: PortalPad
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

	# Three channels (flood strips) as self-contained Channel objects — each owns its bed + water visual and its
	# scheduler-driven flood cadence. Phased 0/1/2 over the period so at least one is always flooding.
	_channels = []
	for i in range(CHANNEL_X.size()):
		var ch := Channel.new()
		ch.name = "Channel%d" % i
		ch.configure(CHANNEL_X[i], CHANNEL_HALF, Z_HALF, CHANNEL_PERIOD, CHANNEL_DUR, CHANNEL_PHASE[i], "wi_ch%d" % i)
		add_child(ch)
		_channels.append(ch)
		_add_label(self, "Channel %d" % (i + 1), Vector3(CHANNEL_X[i], 1.4, 0.0), Color(0.4, 0.75, 0.85))

	# Capbage tight hides (×3) on the near bank.
	for j in range(CAPBAGE_POS.size()):
		_build_capbage(CAPBAGE_POS[j], j)

	# The flure (near bank) — a self-contained Flure object that owns its glow, outline + lure logic. The chunk just
	# composes it: place it + inject the hunters it lures. (First of the modular gameplay objects.)
	var enemy_ids: Array = []
	for spec in ENEMY_SPECS:
		enemy_ids.append(str(spec["id"]))
	_flure = Flure.new()
	_flure.name = "Flure"
	_flure.configure(_get_game_state(), FLURE_POS, enemy_ids, FLURE_ATTRACT, 1.6, Color(0.95, 0.78, 0.2))
	add_child(_flure)
	_register_interactable(_flure)   # into _interactables + host binding, like every other interactable
	_flure.flure_activated.connect(_on_flure_activated)

	# Portal — a bidirectional pair of self-contained Portal objects. Each owns its glow + outline + teleport;
	# the chunk just places them pointed at each other. Only the activating member crosses (whoever arrives first).
	_portal_near = _build_portal("PortalNear", PORTAL_IN_POS, PORTAL_OUT_POS)
	_add_label(self, "PORTAL", PORTAL_IN_POS + Vector3(0.0, 1.6, 0.0), Color(0.6, 0.5, 1.0))
	_portal_far = _build_portal("PortalFar", PORTAL_OUT_POS, PORTAL_IN_POS)

	_spawn_enemies()
	reset_preview_state()
	_set_preview_step("channels_wash_intro_start")

func _build_portal(node_name: String, pos: Vector3, dest: Vector3) -> PortalPad:
	var p := PortalPad.new()
	p.name = node_name
	p.configure(_get_game_state(), pos, dest, PORTAL_RADIUS, Color(0.55, 0.42, 0.98))
	add_child(p)
	_register_interactable(p)
	p.stepped_through.connect(_on_portal_stepped)
	return p

func _on_portal_stepped(_who: String, _dest: Vector3) -> void:
	if _phase in ["complete", "failed"]:
		return
	_say("// PORTAL // through")

func _build_capbage(pos: Vector3, j: int) -> void:
	# A self-contained Capbage object: it owns its leaf-head visual, its outline, and its hide radius. The chunk
	# composes it + aggregates concealment from each Capbage's conceals() in _update.
	var cap := Capbage.new()
	cap.name = "Capbage%d" % j
	cap.configure(_get_game_state(), pos, CAPBAGE_RADIUS)
	add_child(cap)
	_register_interactable(cap)
	cap.tucked_in.connect(func() -> void: _say("// HIDE // tucked into the Capbage"))
	_capbages.append(cap)
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
	for ch in _channels:
		ch.start(sched)   # each Channel owns its own scheduler-driven cadence

## Force channel `i` to flood now — scripted beats / tests. (The cadence itself lives in the Channel object.)
func _channel_onset(i: int) -> void:
	if _phase in ["complete", "failed"]:
		return
	if i >= 0 and i < _channels.size() and is_instance_valid(_channels[i]):
		_channels[i].flood_now()

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

	# Capbage concealment: a party member inside ANY Capbage's hide radius is fully undetectable (tight hide).
	# Each Capbage owns its own conceals() check; the chunk just aggregates (FULL if inside one, else NONE).
	for cid in PARTY_IDS:
		if not gs.characters.has(cid):
			continue
		var p := _get_character_position(cid)
		var hidden := false
		for cap in _capbages:
			if is_instance_valid(cap) and cap.conceals(p):
				hidden = true
				break
		gs.set_character_concealment(cid, GameState.CONCEAL_FULL if hidden else GameState.CONCEAL_NONE)

	# Drown: an enemy caught in a flooding channel is swept off (the wash kills it). Each Channel owns floods_at().
	for enemy in _enemies:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		var ep: Vector3 = gs.get_position(enemy.char_id) if gs.characters.has(enemy.char_id) else enemy.position
		if _any_channel_floods_at(ep.x, ep.z):
			_drown_enemy(enemy)

	# The wash flushes PLAYERS too: a member standing in a flooding channel is swept back to the section start
	# (for now the left bank; eventually a spot near Endo's junction). Snapping them out clears the footprint, so
	# it can't re-fire every frame. The portal is the safe way across — the channels themselves are lethal.
	for cid in PARTY_IDS:
		if not gs.characters.has(cid):
			continue
		var mp := _get_character_position(cid)
		if _any_channel_floods_at(mp.x, mp.z):
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

## Light the flure (the lure logic lives in the Flure object now; this just gates on phase + delegates). Kept for
## the data-layer playthrough + tests that trigger it by name. The Flure also self-fires on a real click.
func activate_flure() -> bool:
	if _phase in ["complete", "failed"] or _flure == null:
		return false
	return _flure.activate()

## The Flure pulled the hunters (via a click or activate_flure) — the CHUNK-level reaction: the beat + the line.
func _on_flure_activated(_pulled: int) -> void:
	if _phase in ["complete", "failed"]:
		return
	_last_outcome = "flure_lit"
	_set_preview_step("channels_wash_intro_flure")
	_say("// FLURE // signal up — the hunters lock onto it")


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
	if _flure != null:
		_flure.reset_flure()
	_drowned = 0
	_drowned_ids = {}
	_washed_back = 0
	_scheduled = false
	_last_outcome = ""
	for ch in _channels:                 # each Channel cancels its own cadence + hides its water
		if is_instance_valid(ch):
			ch.reset()
	_set_preview_step("channels_wash_intro_start")

func get_preview_state() -> Dictionary:
	var any_flooding := false
	var flooding: Array = []
	for ch in _channels:
		var f: bool = is_instance_valid(ch) and ch.is_flooding()
		flooding.append(f)
		if f:
			any_flooding = true
	var enemies_alive := 0
	for enemy in _enemies:
		if is_instance_valid(enemy) and enemy.is_alive():
			enemies_alive += 1
	return {
		"phase": _phase,
		"complete": _phase == "complete",
		"flure_active": _flure.is_active() if _flure != null else false,
		"any_channel_flooding": any_flooding,
		"flooding": flooding,
		"drowned": _drowned,
		"enemies_alive": enemies_alive,
		"flure_attract_range": FLURE_ATTRACT,
		"player_sense_range": ENEMY_DETECT,
		"last_outcome": _last_outcome,
	}

## True if any channel is flooding at (x, z) right now — the per-frame drown/wash check delegates to each Channel.
func _any_channel_floods_at(x: float, z: float) -> bool:
	for ch in _channels:
		if is_instance_valid(ch) and ch.floods_at(x, z):
			return true
	return false
