extends "res://scripts/scene_chunks/scene_chunk.gd"

## WASH RELAY — the early-stretch traversal gauntlet.
##
## A linear run of distinct PUZZLE SECTIONS, each a timed water hazard on one shared cadence. Standing
## in an ACTIVE section's footprint when it floods washes you back to the start shelter. Sections differ
## by TYPE (the verb) and by how they're DISABLED for the party:
##   flush   — a lowered channel floods            (disable: OVERRIDE — a runner crosses + presses it)
##   current — water washes across a narrow walk    (disable: TIMING  — read the cadence, cross between)
##   jet     — floor nozzles erupt                  (disable: OVERRIDE)
##   plate   — a gap whose bridge needs a held plate (disable: PLATE  — one stays on the plate for others)
##   sluice  — a gate slams the threshold           (disable: TIMING; a REAL blocker while closed)
## The back half adds a THREAT layer over the wash — guards that hunt the party, hide alcoves that
## conceal you from them, and flures that draw a guard off its post:
##   patrol  — a guard ROAMS the section; duck into the hide alcove (full concealment) + time the wash
##   lure    — a SENTRY holds a chokepoint; fire the flure to distract + draw it, then cross
## A guard that lands a hit shoves you into the channel (washed to the start shelter — same consequence).
## Reach the chunk end with the whole party; a RETURN device pulls washed members back up.
## All hazards fire on the gameplay SCHEDULER (recurring per-section onsets) — fast-forward + replay safe.

const EnemyScript := preload("res://scripts/game/ai/enemy.gd")
const ChannelsArc := preload("res://scripts/game/world/channels_arc.gd")
const StretchGenerator := preload("res://scripts/generation/stretch_generator.gd")

const PARTY_IDS := ["aster", "peris", "endo"]
const START_POS := Vector3(3.0, 0.5, 0.0)
const SPAWNS := {
	"aster": Vector3(3.0, 0.5, 0.0), "peris": Vector3(2.0, 0.5, 1.2), "endo": Vector3(2.0, 0.5, -1.2),
}
# The gauntlet, front (pure wash) to back (wash + threats). Each section may override the shared cadence
# with its own "period"/"dur" (variety: tight frantic windows vs slow long-danger surges).
const SECTIONS := [
	{"type": "flush",        "x0": 6.0,  "x1": 11.0, "phase": 0.0, "disable": "override"},
	{"type": "current",      "x0": 14.0, "x1": 19.0, "phase": 2.5, "disable": "timing", "period": 4.0},   # fast beat
	{"type": "jet",          "x0": 22.0, "x1": 27.0, "phase": 1.2, "disable": "override"},
	{"type": "plate",        "x0": 30.0, "x1": 35.0, "phase": 3.6, "disable": "plate"},
	{"type": "sluice",       "x0": 38.0, "x1": 41.0, "phase": 0.8, "disable": "timing"},
	{"type": "patrol",       "x0": 46.0, "x1": 53.0, "phase": 4.0, "disable": "timing"},          # roaming guard + alcove
	{"type": "lure",         "x0": 56.0, "x1": 61.0, "phase": 1.6, "disable": "timing"},          # sentry + flure
	{"type": "basin",        "x0": 64.0, "x1": 71.0, "phase": 0.0, "disable": "override",
		"period": 8.0, "dur": 2.6},                                                               # wide, slow, long danger — guarded
	{"type": "double_plate", "x0": 74.0, "x1": 79.0, "phase": 2.0, "disable": "double_plate"},    # TWO plates, both held
]
const FLOOR_Z_HALF := 4.0
const FLOOR_MIN_X := -1.0
const FLOOR_MAX_X := 87.0
const CHUNK_END_X := 84.0
# Connect-back devices at the CHUNK END (link back to the stretch start) — positions track the end.
const TERMINAL_POS := Vector3(CHUNK_END_X, 0.5, 2.5)     # telephone stranded crew up — one party call, instant
const SLOPEROPE_POS := Vector3(CHUNK_END_X, 0.5, -2.5)   # drop a climbing line down to the start shelter
const CLIMB_POS := Vector3(5.0, 0.5, 2.5)                # start — a washed member climbs the dropped line up
const RETURN_LANDING := Vector3(CHUNK_END_X - 1.0, 0.5, 0.0)   # where recovered crew rejoin the party
const FLOW_PERIOD := 6.0            # default cadence (a section's "period" overrides it)
const FLOOD_DURATION := 1.4         # default danger window (a section's "dur" overrides it)
const FIRST_FLOOD := 2.5
const PLATE_RADIUS := 1.4           # how close a character must be to "hold" a plate
const DOUBLE_PLATE_Z := 2.5         # the two pads of a double-plate sit at ±this z

# --- Threat layer (guards / hide alcoves / lures, laid over the guarded sections) ---
const HIDE_ALCOVES := [
	{"pos": Vector3(49.5, 0.5, 3.3), "radius": 1.9},   # a nook in the patrol section
	{"pos": Vector3(67.5, 0.5, 3.3), "radius": 1.9},   # a nook beside the guarded basin
]
const ENEMY_SPECS := [
	{"id": "ch_roamer", "spawn": Vector3(49.5, 0.5, 0.0), "kind": "roam",  "radius": 2.6, "speed": 3.0, "range": 5.5},
	{"id": "ch_sentry", "spawn": Vector3(58.5, 0.5, 0.0), "kind": "guard", "radius": 0.0, "speed": 4.0, "range": 6.0},
	{"id": "ch_basin",  "spawn": Vector3(67.5, 0.5, 0.0), "kind": "roam",  "radius": 3.0, "speed": 3.2, "range": 5.5},
]
const LURE_SPECS := [{"pos": Vector3(54.0, 0.5, 2.8), "target": "ch_sentry"}]
const LURE_DURATION := 9.0

# --- Branch puzzle offshoots (built USING the archetype generation framework) ---
# At each GAP between sections, a puzzle fragment branches OUT away from the spiral: on the helix, +lane
# is a RADIAL spoke jutting off the deck edge (lane 4 = the deck rim) out to the pad. One generated stretch
# (StretchGenerator, node_count = gap count) supplies an archetype + content per branch; a guarded branch
# also spawns a roamer (capped). Branches are OPTIONAL reward detours — a salvage cache pays off the climb
# out and back; the gaps themselves stay walkable, so they never block the main run.
const BRANCH_S_SPAN := 3.0          # branch footprint along s (fits inside every gap)
const BRANCH_HALF_S := 1.5
const BRANCH_NECK_LANE := 3.5       # walkable region starts here (overlaps the deck rim at lane 4 -> connected)
const BRANCH_OUTER_LANE := 10.0     # walkable region reaches this far out
const BRANCH_DECK_CENTER_LANE := 7.0
const BRANCH_LANE_SPAN := 6.0       # the deck plank spans lane 4..10 radially
const BRANCH_PAD_LANE := 8.5        # where the cache + content sit
const BRANCH_GUARD_CAP := 3         # at most this many branches get a roaming guard (perf + difficulty)
const BRANCH_GEN_SEED := 4727
const BRANCH_REWARD := 1

var _branches: Array = []           # per gap: {gap, mid_x, pad_lane, archetype, content_count, collected, cache, guard}
var _branch_loot := 0
var _branch_root: Node3D
var _branch_guard_spawns := {}      # guard id -> flat spawn (so reset re-snaps branch guards too)

var _phase := "ready"
var _override_locked := []         # per section — an override has been pressed (latched)
var _flooding := []                # cosmetic surge window
var _flood_counts := []            # per section — how many surges have fired (cadence variety / tests)
var _plate_held := []              # per section — all the section's plates are held this frame
var _sluice_blocked := []          # per section — the sluice gate cells are currently walled off
var _washed := {}
var _scheduled := false
var _flow_strips: Array = []
var _enemies: Array = []
var _lure_until: Array = []        # per lure — scheduler tick the distraction ends (<=0 = inactive)
var _lure_meshes: Array = []
var _sloperope_deployed := false   # the chunk-end line has been dropped (the start climb point is live)
var _debug_tick := 0               # throttles the CHANNELS_DEBUG position log
var _rope_mesh: MeshInstance3D

# --- Build ---

func _section_color(t: String) -> Color:
	match t:
		"flush":   return Color(0.15, 0.30, 0.55)
		"current": return Color(0.20, 0.45, 0.70)
		"jet":     return Color(0.40, 0.55, 0.85)
		"plate":   return Color(0.55, 0.35, 0.10)
		"sluice":  return Color(0.45, 0.20, 0.10)
		"patrol":  return Color(0.55, 0.18, 0.20)
		"lure":    return Color(0.55, 0.30, 0.50)
		"basin":   return Color(0.12, 0.35, 0.60)
		"double_plate": return Color(0.60, 0.40, 0.10)
	return Color(0.2, 0.3, 0.5)

func _build_chunk() -> void:
	_wdbg("build_chunk start")
	var fcx := (FLOOR_MIN_X + FLOOR_MAX_X) * 0.5
	var fw := FLOOR_MAX_X - FLOOR_MIN_X
	_add_floor(self, Vector3(fcx, -0.05, 0.0), Vector3(fw, 0.1, FLOOR_Z_HALF * 2.0), Color(0.10, 0.11, 0.13))
	_add_floor(self, START_POS + Vector3(-1.0, -0.05, 0.0), Vector3(8.0, 0.12, FLOOR_Z_HALF * 2.0 + 1.0), Color(0.09, 0.13, 0.16))
	var wc := Color(0.13, 0.14, 0.16)
	_add_box(self, Vector3(fcx, 1.6, -FLOOR_Z_HALF - 0.2), Vector3(fw, 3.2, 0.4), wc)
	_add_box(self, Vector3(fcx, 1.6, FLOOR_Z_HALF + 0.2), Vector3(fw, 3.2, 0.4), wc)
	# one large pipe spanning the gauntlet (the shared flow source)
	var px0: float = SECTIONS[0]["x0"]; var px1: float = SECTIONS[SECTIONS.size() - 1]["x1"]
	_add_box(self, Vector3((px0 + px1) * 0.5, 4.4, FLOOR_Z_HALF - 0.4), Vector3(px1 - px0 + 2.0, 1.2, 1.2), Color(0.2, 0.19, 0.18))

	for i in range(SECTIONS.size()):
		var s: Dictionary = SECTIONS[i]
		var t := str(s["type"]); var x0: float = s["x0"]; var x1: float = s["x1"]; var cx := (x0 + x1) * 0.5; var w := x1 - x0
		# per-type graybox dressing (distinct silhouettes)
		match t:
			"flush":
				_add_box(self, Vector3(cx, -0.18, 0.0), Vector3(w, 0.2, FLOOR_Z_HALF * 1.6), Color(0.06, 0.08, 0.1))   # lowered channel
				_add_box(self, Vector3(cx, 3.4, FLOOR_Z_HALF - 0.4), Vector3(1.0, 0.9, 0.9), Color(0.22, 0.21, 0.2))   # spout
			"current":
				_add_box(self, Vector3(cx, -0.12, FLOOR_Z_HALF * 0.7), Vector3(w, 0.3, 2.2), Color(0.06, 0.08, 0.1))
				_add_box(self, Vector3(cx, -0.12, -FLOOR_Z_HALF * 0.7), Vector3(w, 0.3, 2.2), Color(0.06, 0.08, 0.1))
			"jet":
				for jx in [x0 + w * 0.25, cx, x1 - w * 0.25]:
					for jz in [-1.6, 0.0, 1.6]:
						_add_box(self, Vector3(jx, 0.04, jz), Vector3(0.6, 0.08, 0.6), Color(0.07, 0.07, 0.09))
			"plate":
				_add_box(self, Vector3(cx, 0.06, 0.0), Vector3(w, 0.12, 1.6), Color(0.12, 0.13, 0.16))                 # the bridge plank
				_add_box(self, Vector3(x0 - 1.2, 0.04, 0.0), Vector3(1.0, 0.1, 1.8), Color(0.55, 0.35, 0.1))          # the pressure plate
			"sluice":
				_add_box(self, Vector3(x0, 1.7, 0.0), Vector3(0.3, 3.4, FLOOR_Z_HALF * 2.0), Color(0.16, 0.16, 0.18))
				_add_box(self, Vector3(x1, 1.7, 0.0), Vector3(0.3, 3.4, FLOOR_Z_HALF * 2.0), Color(0.16, 0.16, 0.18))
				_add_box(self, Vector3(cx, 3.3, 0.0), Vector3(w, 0.5, FLOOR_Z_HALF * 2.0), Color(0.16, 0.16, 0.18))
			"patrol":
				_add_box(self, Vector3(cx, 0.015, 0.0), Vector3(w, 0.03, FLOOR_Z_HALF * 1.6), Color(0.08, 0.07, 0.08))   # the guard's open beat
			"lure":
				for zz in [-1.0, 1.0]:
					_add_box(self, Vector3(cx, 1.2, zz * (FLOOR_Z_HALF - 1.0)), Vector3(w, 2.4, 2.0), Color(0.14, 0.13, 0.15))  # chokepoint walls pinch the path
			"basin":
				_add_box(self, Vector3(cx, -0.3, 0.0), Vector3(w, 0.4, FLOOR_Z_HALF * 1.9), Color(0.05, 0.07, 0.09))   # a wide, deep lowered basin
				for sx in [x0 + w * 0.2, cx, x1 - w * 0.2]:
					_add_box(self, Vector3(sx, 3.6, FLOOR_Z_HALF - 0.4), Vector3(1.1, 1.0, 1.1), Color(0.22, 0.21, 0.2))   # multiple spouts
			"double_plate":
				_add_box(self, Vector3(cx, 0.06, 0.0), Vector3(w, 0.12, 1.4), Color(0.12, 0.13, 0.16))                 # the bridge plank
				for zz in [-DOUBLE_PLATE_Z, DOUBLE_PLATE_Z]:
					_add_box(self, Vector3(x0 - 1.2, 0.04, zz), Vector3(1.0, 0.1, 1.6), Color(0.6, 0.4, 0.1))          # two pressure plates
		# the active-flow indicator strip (pulses while flooding)
		var strip := _add_box(self, Vector3(cx, 0.03, 0.0), Vector3(w, 0.06, FLOOR_Z_HALF * 1.7), _section_color(t))
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _section_color(t) * 0.6; mat.emission_enabled = true
		mat.emission = _section_color(t); mat.emission_energy_multiplier = 0.4
		strip.material_override = mat
		_flow_strips.append(strip)
		# the disable control: an override console past the section, or a held plate before it
		if str(s["disable"]) == "override":
			var ov := _add_interactable(self, "Override%d" % i, "Flow override", Vector3(x1 + 1.5, 0.5, 0.0),
				"OVERRIDE", "", 1.0, true, 1.6, Interactable.InteractableType.HOLD_ACTION)
			ov.interacted.connect(func() -> void: _on_override(i))
	_wdbg("sections built")
	_build_threats()
	_wdbg("threats built")
	_build_connect_backs()
	_wdbg("connect-backs built")
	_build_branches()
	_wdbg("branches built")

# The connect-back points at the chunk end (plus the start climb point the sloperope feeds).
func _build_connect_backs() -> void:
	# TERMINAL — telephone stranded crew up; one call at the chunk end, instant.
	var term := _add_interactable(self, "Terminal", "Telephone up", TERMINAL_POS,
		"TERMINAL", "", 1.2, false, 1.7, Interactable.InteractableType.HOLD_ACTION)
	term.interacted.connect(func() -> void: _on_terminal())
	var tm := _add_box(self, TERMINAL_POS + Vector3(0.0, 0.4, 0.0), Vector3(0.8, 1.5, 0.4), Color(0.1, 0.4, 0.45))
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.1, 0.4, 0.45); tmat.emission_enabled = true
	tmat.emission = Color(0.2, 0.9, 1.0); tmat.emission_energy_multiplier = 2.0; tm.material_override = tmat
	# SLOPEROPE — drop a climbing line down to the start; the party deploys it once.
	var rope := _add_interactable(self, "Sloperope", "Drop sloperope", SLOPEROPE_POS,
		"DROP LINE", "", 1.2, false, 1.7, Interactable.InteractableType.HOLD_ACTION)
	rope.interacted.connect(func() -> void: _on_sloperope())
	_add_box(self, SLOPEROPE_POS + Vector3(0.0, 1.4, 0.0), Vector3(0.4, 2.8, 0.4), Color(0.3, 0.22, 0.12))   # the reel post
	# CLIMB POINT at the start — a washed member climbs the dropped line back up to the chunk end.
	var climb := _add_interactable(self, "ClimbLine", "Climb the line", CLIMB_POS,
		"CLIMB", "", 1.4, false, 1.7, Interactable.InteractableType.HOLD_ACTION)
	climb.interacted.connect(func() -> void: _on_climb())
	_rope_mesh = _add_box(self, CLIMB_POS + Vector3(0.0, 1.4, 0.0), Vector3(0.16, 2.8, 0.16), Color(0.25, 0.18, 0.1))
	_rope_mesh.visible = false   # the line only appears once dropped from the chunk end

# --- Branch puzzle offshoots ---

func _wdbg(msg: String) -> void:
	if OS.has_environment("PREVIEW_DEBUG"):
		print("[wash_relay] → ", msg)

# The mid-s of each GAP between consecutive sections (where a branch attaches).
func _gap_mids() -> Array:
	var mids: Array = []
	for i in range(SECTIONS.size() - 1):
		mids.append((float(SECTIONS[i]["x1"]) + float(SECTIONS[i + 1]["x0"])) * 0.5)
	return mids

# Generate ONE stretch (one node per gap) through the archetype framework — each node hands a branch its
# archetype + content placements. Falls back to a fixed archetype rotation so the offshoots still build if
# the generation catalog is unavailable (the chunk never hard-fails on missing data).
func _generate_branch_nodes(count: int) -> Array:
	var spec: Dictionary = StretchGenerator.generate({
		"id": "wash_relay_branches", "title": "Wash Relay Branches",
		"seed": BRANCH_GEN_SEED, "complexity_tier": "developing", "progression_stage": 3,
		"budget": {"node_count": count, "branch_count": 0},
	})
	if bool(spec.get("ok", false)):
		var nodes: Array = spec.get("nodes", [])
		if nodes.size() >= count:
			return nodes.slice(0, count)
	var fallback: Array = []
	var names := ["Plant as tool", "Stealth-and-time", "Carry the heavy thing", "Redirected enemy aggression",
		"Lysate forage cache", "Narrative beat", "Plant as tool", "Stealth-and-time"]
	for i in range(count):
		fallback.append({"archetype_name": names[i % names.size()], "content_placements": [], "enemies": []})
	return fallback

func _build_branches() -> void:
	_branches.clear()
	_branch_loot = 0
	_branch_guard_spawns.clear()
	_branch_root = Node3D.new()
	_branch_root.name = "Branches"
	add_child(_branch_root)
	var mids := _gap_mids()
	_wdbg("generating %d branch nodes" % mids.size())
	var nodes := _generate_branch_nodes(mids.size())
	_wdbg("generated %d nodes" % nodes.size())
	var guards_spawned := 0
	for g in range(mids.size()):
		var mid: float = mids[g]
		var node: Dictionary = nodes[g] if g < nodes.size() else {}
		var archetype := str(node.get("archetype_name", "Offshoot"))
		var placements: Array = node.get("content_placements", [])
		# The radial plank: juts off the deck rim (lane 4) out to the pad (lane 10), pre-warped onto the helix.
		var deck_color := Color(0.12, 0.14, 0.17)
		_add_warped_deck(mid, BRANCH_DECK_CENTER_LANE, Vector3(BRANCH_LANE_SPAN, 0.2, BRANCH_S_SPAN), deck_color)
		# A marker post at the deck rim so the offshoot reads as a turn-off from the main run.
		_add_warped_box(mid, BRANCH_NECK_LANE + 0.4, Vector3(0.4, 1.6, 0.4), Color(0.2, 0.5, 0.55), Color(0.2, 0.7, 0.8), 0.8)
		# The archetype's content placements, clustered on the pad (graybox identity of the puzzle).
		var content_count := _build_branch_content(mid, placements)
		# Reward cache — authored FLAT (the host warp pass lifts every interactable onto the helix); its mesh
		# is a CHILD so it rides the warp and stays visible (it isn't in the GLB the flat-graybox hide replaces).
		var cache := _add_interactable(self, "BranchCache%d" % g, "Salvage cache",
			Vector3(mid, 0.5, BRANCH_PAD_LANE), "SALVAGE", "", 1.2, true, 1.6,
			Interactable.InteractableType.HOLD_ACTION, false)
		var cm := MeshInstance3D.new()
		var cb := BoxMesh.new(); cb.size = Vector3(0.7, 0.7, 0.7); cm.mesh = cb
		cm.material_override = _make_material(Color(0.7, 0.6, 0.2), Color(1.0, 0.85, 0.25), 1.4)
		cm.position = Vector3(0.0, 0.45, 0.0)
		cache.add_child(cm)
		cache.interacted.connect(func() -> void: _on_branch_cache(g))
		# A guarded branch (the archetype carries an enemy) spawns a roamer on the pad — a real risk detour.
		var guard = null
		if guards_spawned < BRANCH_GUARD_CAP and _branch_has_enemy(node):
			guard = _spawn_branch_guard(g, mid)
			if guard != null:
				guards_spawned += 1
		_branches.append({
			"gap": g, "mid_x": mid, "pad_lane": BRANCH_PAD_LANE, "archetype": archetype,
			"content_count": content_count, "collected": false, "cache": cache, "guard": guard,
		})

func _branch_has_enemy(node: Dictionary) -> bool:
	if not (node.get("enemies", []) as Array).is_empty():
		return true
	for p in node.get("content_placements", []):
		if (p is Dictionary) and str((p as Dictionary).get("category", "")) == "enemies":
			return true
	return false

# Lay the archetype's content placements (capped) around the pad centre, pre-warped onto the helix.
func _build_branch_content(mid: float, placements: Array) -> int:
	var offsets := [Vector2(-0.8, -0.7), Vector2(0.8, -0.7), Vector2(0.0, 0.9)]   # (s, lane) relative to pad
	var count := 0
	for raw in placements:
		if count >= offsets.size():
			break
		if not (raw is Dictionary):
			continue
		var p := raw as Dictionary
		var off: Vector2 = offsets[count]
		var sz := _branch_marker_size(p.get("size", []))
		_add_warped_box(mid + off.x, BRANCH_PAD_LANE + off.y, sz,
			_branch_content_color(str(p.get("category", ""))), Color.BLACK, 0.0)
		count += 1
	return count

func _branch_marker_size(raw_size: Variant) -> Vector3:
	if raw_size is Array and (raw_size as Array).size() >= 3:
		var a := raw_size as Array
		return Vector3(clampf(float(a[0]), 0.4, 1.2), clampf(float(a[1]), 0.4, 1.2), clampf(float(a[2]), 0.4, 1.2))
	return Vector3(0.7, 0.7, 0.7)

func _branch_content_color(category: String) -> Color:
	match category:
		"flora": return Color(0.25, 0.55, 0.3)
		"enemies": return Color(0.6, 0.2, 0.22)
		"structures": return Color(0.35, 0.4, 0.5)
	return Color(0.4, 0.4, 0.45)

func _spawn_branch_guard(g: int, mid: float):
	var gs = _get_game_state()
	if gs == null:
		return null
	var spawn := Vector3(mid, 0.5, BRANCH_PAD_LANE)
	var enemy = EnemyScript.new()
	enemy.name = "BranchGuard_%d" % g
	enemy.position = spawn
	enemy.move_speed = 2.8
	enemy.detection_range = 4.5
	enemy.char_id = "branch_guard_%d" % g
	enemy.game_state = gs
	enemy._detection_targets.assign(PARTY_IDS)
	_branch_root.add_child(enemy)
	gs.register_character(enemy.char_id, spawn, enemy.move_speed, {"detection_range": enemy.detection_range})
	if enemy.has_method("activate"):
		enemy.activate()
	enemy.set_roam(spawn, 1.6)
	enemy.hit_target.connect(func(tid: String, _dmg: float) -> void: _on_enemy_hit(tid))
	_enemies.append(enemy)
	_branch_guard_spawns[enemy.char_id] = spawn
	return enemy

# A box pre-warped onto the helix: authored as (lane-extent, height, s-extent) so basis_at(s) aligns local
# x with the radial (lane) axis and local z with the tangent (s) axis. Walk-on decks also get layer-1
# collision (the GLB's collision doesn't cover this new geometry, so the player's ground ray must hit it).
func _branch_warp_xform(s: float, lane_center: float) -> Transform3D:
	return Transform3D(ChannelsArc.basis_at(s), ChannelsArc.arc_pos(s, lane_center))

func _add_warped_box(s: float, lane_center: float, size: Vector3, color: Color, emission := Color.BLACK, energy := 0.0) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new(); box.size = size; mesh.mesh = box
	mesh.material_override = _make_material(color, emission, energy)
	mesh.transform = _branch_warp_xform(s, lane_center)
	_branch_root.add_child(mesh)
	return mesh

func _add_warped_deck(s: float, lane_center: float, size: Vector3, color: Color) -> void:
	var mesh := _add_warped_box(s, lane_center, size, color)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.transform = mesh.transform
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new(); shape.size = size
	col.shape = shape
	body.add_child(col)
	_branch_root.add_child(body)

func _on_branch_cache(g: int) -> void:
	if g < 0 or g >= _branches.size():
		return
	if bool(_branches[g].get("collected", false)):
		return
	_branches[g]["collected"] = true
	_branch_loot += BRANCH_REWARD
	_say("// SALVAGE // cache stripped (%d)" % _branch_loot)

# --- Threat layer: hide alcoves, flures, guards ---

func _build_threats() -> void:
	for a in HIDE_ALCOVES:
		var p: Vector3 = a["pos"]
		_add_box(self, Vector3(p.x, 2.0, p.z + 0.6), Vector3(2.4, 0.3, 1.2), Color(0.10, 0.10, 0.12))   # overhang roof
		_add_box(self, Vector3(p.x, 1.2, p.z + 1.1), Vector3(2.4, 2.4, 0.3), Color(0.11, 0.11, 0.13))   # back wall
		var glow := _add_box(self, Vector3(p.x, 0.03, p.z), Vector3(2.0, 0.05, 1.4), Color(0.08, 0.14, 0.18))
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.08, 0.14, 0.18); gm.emission_enabled = true
		gm.emission = Color(0.15, 0.45, 0.55); gm.emission_energy_multiplier = 0.5
		glow.material_override = gm
	for li in range(LURE_SPECS.size()):
		var lp: Vector3 = LURE_SPECS[li]["pos"]
		var bulb := _add_box(self, Vector3(lp.x, 0.7, lp.z), Vector3(0.5, 0.9, 0.5), Color(0.4, 0.25, 0.06))
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.4, 0.25, 0.06); bm.emission_enabled = true
		bm.emission = Color(1.0, 0.55, 0.12); bm.emission_energy_multiplier = 0.6
		bulb.material_override = bm
		_lure_meshes.append(bulb)
		_lure_until.append(-1.0)
		var idx := li
		var dev := _add_interactable(self, "Flure%d" % li, "Fire flure", lp,
			"FLURE", "", 1.0, true, 1.4, Interactable.InteractableType.HOLD_ACTION)
		dev.interacted.connect(func() -> void: _on_lure(idx))
	for spec in ENEMY_SPECS:
		_spawn_enemy(spec)

func _spawn_enemy(spec: Dictionary) -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	var enemy = EnemyScript.new()
	enemy.name = "Guard_%s" % str(spec["id"])
	enemy.position = spec["spawn"]
	enemy.move_speed = float(spec.get("speed", 3.0))
	enemy.detection_range = float(spec.get("range", 5.5))
	enemy.char_id = str(spec["id"])
	enemy.game_state = gs
	enemy._detection_targets.assign(PARTY_IDS)
	add_child(enemy)
	gs.register_character(enemy.char_id, enemy.position, enemy.move_speed, {"detection_range": enemy.detection_range})
	if enemy.has_method("activate"):
		enemy.activate()
	if str(spec.get("kind", "guard")) == "roam":
		enemy.set_roam(spec["spawn"], float(spec.get("radius", 2.6)))
	enemy.hit_target.connect(func(tid: String, _dmg: float) -> void: _on_enemy_hit(tid))
	_enemies.append(enemy)

func _enemy_spawn_for(id: String) -> Vector3:
	for spec in ENEMY_SPECS:
		if str(spec["id"]) == id:
			return spec["spawn"]
	if _branch_guard_spawns.has(id):
		return _branch_guard_spawns[id]
	return Vector3.ZERO

func _on_enemy_hit(target_id: String) -> void:
	if target_id in PARTY_IDS:
		_wash_character(target_id)   # the guard shoves you into the channel -> back to the start shelter

func _on_lure(idx: int) -> void:
	if idx < 0 or idx >= LURE_SPECS.size():
		return
	var l: Dictionary = LURE_SPECS[idx]
	var target := str(l["target"])
	var lp: Vector3 = l["pos"]
	while _lure_until.size() <= idx:
		_lure_until.append(-1.0)
	_lure_until[idx] = _get_scheduler_tick() + LURE_DURATION
	_set_lure_emission(idx, 3.0)
	var gs = _get_game_state()
	if gs != null:
		for enemy in _enemies:
			if is_instance_valid(enemy) and enemy.char_id == target and gs.characters.has(target):
				gs.set_character_distracted(target, true)   # reach shrinks: it won't notice a runner keeping distance
				gs.command_move_to_pos(target, lp)           # and it walks off its post toward the song
	var sched = _get_scheduler()
	if sched != null:
		sched.schedule_after(LURE_DURATION, func() -> void: _on_lure_expired(idx), "wash_lure_%d" % idx)
	_say("// FLURE SINGS // guard drawn")

func _on_lure_expired(idx: int) -> void:
	if idx < _lure_until.size():
		_lure_until[idx] = -1.0
	_set_lure_emission(idx, 0.6)
	var target := str(LURE_SPECS[idx]["target"])
	var gs = _get_game_state()
	if gs != null and gs.characters.has(target):
		gs.set_character_distracted(target, false)
		gs.command_move_to_pos(target, _enemy_spawn_for(target))

func _set_lure_emission(idx: int, e: float) -> void:
	if idx < _lure_meshes.size() and is_instance_valid(_lure_meshes[idx]):
		var m := _lure_meshes[idx].material_override as StandardMaterial3D
		if m != null:
			m.emission_energy_multiplier = e

func _lure_active() -> bool:
	var now := _get_scheduler_tick()
	for u in _lure_until:
		if float(u) > now:
			return true
	return false

# --- Wash cadence (scheduler-driven; fires at exact ticks) ---

func _ensure_scheduled() -> void:
	if _scheduled:
		return
	var sched = _get_scheduler()
	if sched == null:
		return
	_scheduled = true
	for i in range(SECTIONS.size()):
		sched.schedule_after(FIRST_FLOOD + float(SECTIONS[i]["phase"]), _make_onset(i), "wash_onset_%d" % i)

func _make_onset(i: int) -> Callable:
	return func() -> void: _flood_onset(i)

func _period(i: int) -> float:
	return float(SECTIONS[i].get("period", FLOW_PERIOD))

func _dur(i: int) -> float:
	return float(SECTIONS[i].get("dur", FLOOD_DURATION))

func _flood_onset(i: int) -> void:
	var sched = _get_scheduler()
	if _phase == "active" and not _section_disabled(i):
		_wash_section(i)
		_flooding[i] = true
		if i < _flood_counts.size():
			_flood_counts[i] += 1
		_set_strip(i, 2.6)
		if str(SECTIONS[i]["type"]) == "sluice":
			_set_sluice(i, true)            # the gate slams shut — the threshold is impassable
		if sched != null:
			sched.schedule_after(_dur(i), func() -> void: _set_flood_off(i), "wash_off_%d" % i)
	if sched != null:
		sched.schedule_after(_period(i), _make_onset(i), "wash_onset_%d" % i)

func _set_flood_off(i: int) -> void:
	_flooding[i] = false
	_set_strip(i, 0.4)
	if i < SECTIONS.size() and str(SECTIONS[i]["type"]) == "sluice":
		_set_sluice(i, false)               # the gate lifts — the threshold opens again

func _section_disabled(i: int) -> bool:
	if bool(_override_locked[i]):
		return true
	var dis := str(SECTIONS[i]["disable"])
	if dis == "plate" or dis == "double_plate":
		return _plate_held[i]               # double_plate: _plate_held is true only when BOTH pads are held
	return false

# The sluice gate is a real movement BLOCKER: while closed, its threshold cells are non-walkable, so
# pathfinding refuses to route a character through (they wait / route around) — not just a wash hazard.
func _sluice_gate_cells(i: int) -> Array:
	var s: Dictionary = SECTIONS[i]
	var gate_x := (float(s["x0"]) + float(s["x1"])) * 0.5
	var gs = _get_game_state()
	var cells: Array = []
	if gs == null or gs.grid == null:
		return cells
	for wz in range(-3, 4):
		cells.append(gs.grid.world_to_grid(Vector3(gate_x, 0.0, float(wz))))
	return cells

func _set_sluice(i: int, closed: bool) -> void:
	if i >= _sluice_blocked.size():
		return
	_sluice_blocked[i] = closed
	var gs = _get_game_state()
	if gs == null or gs.grid == null:
		return
	for cell in _sluice_gate_cells(i):
		if closed:
			gs.grid.add_dynamic_blocker(cell, "sluice_%d" % i)
		else:
			gs.grid.remove_dynamic_blocker(cell)

func _wash_section(i: int) -> void:
	var s: Dictionary = SECTIONS[i]
	var x0: float = s["x0"]; var x1: float = s["x1"]
	for char_id in PARTY_IDS:
		if _washed.has(char_id):
			continue
		var p := _get_character_position(char_id)
		if p.x >= x0 and p.x <= x1 and abs(p.z) <= FLOOR_Z_HALF:
			_wash_character(char_id)

func _wash_character(char_id: String) -> void:
	_washed[char_id] = true
	var gs = _get_game_state()
	if gs != null:
		gs.command_stop(char_id)   # cancel any in-flight move so the runner stays knocked back, not walking on
	_set_character_position(char_id, START_POS)

# --- Interactions ---

func _on_override(i: int) -> void:
	if i < 0 or i >= _override_locked.size():
		return
	_override_locked[i] = true
	_set_flood_off(i)
	_set_strip(i, 0.15)
	_say("// SECTION %d FLOW // OVERRIDE ENGAGED" % (i + 1))

func _recover_washed() -> int:
	var n := _washed.size()
	for char_id in _washed.keys():
		_set_character_position(char_id, RETURN_LANDING)
	_washed.clear()
	return n

func _on_terminal() -> void:
	var n := _recover_washed()
	_say("// TERMINAL // %d crew telephoned up" % n if n > 0 else "// TERMINAL // no crew stranded")

func _on_sloperope() -> void:
	_sloperope_deployed = true
	if is_instance_valid(_rope_mesh):
		_rope_mesh.visible = true
	_say("// SLOPEROPE DROPPED // climb it from the start")

func _on_climb() -> void:
	if not _sloperope_deployed:
		_say("// NO LINE // drop the sloperope from the chunk end first")
		return
	var n := _recover_washed()
	if n > 0:
		_say("// CLIMBED UP // %d crew recovered" % n)

func _set_strip(i: int, energy: float) -> void:
	if i < _flow_strips.size() and is_instance_valid(_flow_strips[i]):
		var mat := _flow_strips[i].material_override as StandardMaterial3D
		if mat != null:
			mat.emission_energy_multiplier = energy

# --- Lifecycle ---

func _process(_delta: float) -> void:
	_update()

func headless_process(_delta: float) -> void:
	_update()

# The pad footprint(s) a section needs HELD to disable it. A plain plate has one; a double_plate has two
# (at ±DOUBLE_PLATE_Z), so two members must stay while the third crosses.
func _plate_footprints(i: int) -> Array:
	var px := float(SECTIONS[i]["x0"]) - 1.2
	if str(SECTIONS[i]["disable"]) == "double_plate":
		return [Vector2(px, -DOUBLE_PLATE_Z), Vector2(px, DOUBLE_PLATE_Z)]
	return [Vector2(px, 0.0)]

## Run with CHANNELS_DEBUG=1 to log each party member's flat DATA position and its warped RENDER position
## (where the node should sit on the helix) once or twice a second — for tracing anomalies like a member
## ending up below the deck.
func _debug_log_positions() -> void:
	if not OS.has_environment("CHANNELS_DEBUG"):
		return
	_debug_tick += 1
	if _debug_tick % 30 != 0:
		return
	var gsd = _get_game_state()
	if gsd == null:
		return
	for cid in PARTY_IDS:
		if gsd.characters.has(cid):
			var d: Vector3 = gsd.get_position(cid)
			var r: Vector3 = gsd.get_render_position(cid)
			print("[channels] %-6s data=(%5.1f,%4.1f,%5.1f) render=(%6.1f,%5.1f,%6.1f) moving=%s" % [cid, d.x, d.y, d.z, r.x, r.y, r.z, gsd.is_moving(cid)])

func _update() -> void:
	if _phase == "ready":
		_phase = "active"
	_ensure_scheduled()
	_debug_log_positions()
	# refresh plate-held state — a section is held only when EVERY one of its pads has a member on it
	for i in range(SECTIONS.size()):
		var dis := str(SECTIONS[i]["disable"])
		if dis != "plate" and dis != "double_plate":
			continue
		var all_held := true
		for fp in _plate_footprints(i):
			var pad_held := false
			for char_id in PARTY_IDS:
				if _washed.has(char_id):
					continue
				var p := _get_character_position(char_id)
				if abs(p.x - fp.x) <= PLATE_RADIUS and abs(p.z - fp.y) <= PLATE_RADIUS:
					pad_held = true
					break
			if not pad_held:
				all_held = false
				break
		if all_held != _plate_held[i]:
			_plate_held[i] = all_held
			_set_strip(i, 0.15 if all_held else 0.4)
	# hide alcoves: a party member tucked in a nook is fully concealed from the guards
	var gsc = _get_game_state()
	if gsc != null and not _enemies.is_empty():
		for cid in PARTY_IDS:
			if not gsc.characters.has(cid):
				continue
			var cp := _get_character_position(cid)
			var hidden := false
			for a in HIDE_ALCOVES:
				if Vector2(cp.x - a["pos"].x, cp.z - a["pos"].z).length() <= float(a["radius"]):
					hidden = true
					break
			gsc.set_character_concealment(cid, GameState.CONCEAL_FULL if hidden else GameState.CONCEAL_NONE)
	if _phase == "active":
		var all_through := true
		for char_id in PARTY_IDS:
			if _get_character_position(char_id).x < CHUNK_END_X:
				all_through = false
				break
		if all_through:
			_phase = "complete"
			_say("// CHUNK CLEAR")

# --- Scene/preview interface ---

## The modeled environment this gauntlet plays inside — the textured channels spiral. It is built along
## the SAME helix as ChannelsArc, so arc_pos(section x, lane z) lands each section on its set piece.
func get_environment_model() -> String:
	return "res://resources/models/channels/channels.glb"

## Installing this on GameState moves the playable system ONTO the helix: the data layer stays flat,
## node followers render through it, and a click on the GLB deck maps back to a flat (s, lane) target.
func get_coord_map():
	return ChannelsCoordMap.new()

## With the textured GLB as the environment, the flat graybox geometry would double the set pieces and
## float below the helix — hide it. Only this chunk's own DIRECT meshes go; the meshless interaction
## zones stay live and the guard nodes (which render through the warp) are untouched.
func hide_flat_graybox() -> void:
	for c in get_children():
		if c is MeshInstance3D:
			c.visible = false

func get_scene_title() -> String:
	return "Wash Relay"

func get_scene_help() -> String:
	return "A long gauntlet of timed water hazards, each on its own beat. Override the flush/jet/basin, hold the plate (and the DOUBLE plate — two members stay) for the bridges, time the fast current and the sluice. Guards prowl the back half: hide in an alcove to slip a roamer, fire the flure to draw the sentry off its chokepoint, and watch the guarded basin. A guard's hit, or standing in a flooding section, shoves you back to the start shelter — telephone up or drop the sloperope to recover."

func get_default_character() -> String:
	return "endo"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate(true)

func get_grid_data() -> Dictionary:
	# The main deck lane, plus one OUTWARD spur per gap (lane 3.5..10) — the branch offshoots. Each spur
	# overlaps the deck rim (lane 4) so it's path-connected; the height grows to admit the outer lane.
	var regions: Array = [{"min": [FLOOR_MIN_X, -FLOOR_Z_HALF], "max": [FLOOR_MAX_X, FLOOR_Z_HALF]}]
	for mid in _gap_mids():
		regions.append({"min": [float(mid) - BRANCH_HALF_S, BRANCH_NECK_LANE], "max": [float(mid) + BRANCH_HALF_S, BRANCH_OUTER_LANE]})
	return {
		"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
		"origin": [-2.0, 0.0, -6.0], "cell_size": 1.0, "width": 92, "height": 18,
		"walkable_regions": regions,
	}

func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors["start_shelter"] = START_POS
	anchors["chunk_end"] = Vector3(CHUNK_END_X + 1.0, 0.5, 0.0)
	anchors["terminal"] = TERMINAL_POS
	anchors["sloperope"] = SLOPEROPE_POS
	anchors["climb_line"] = CLIMB_POS
	for i in range(SECTIONS.size()):
		anchors["section_%s" % SECTIONS[i]["type"]] = Vector3((float(SECTIONS[i]["x0"]) + float(SECTIONS[i]["x1"])) * 0.5, 0.5, 0.0)
	for ai in range(HIDE_ALCOVES.size()):
		anchors["hide_alcove_%d" % ai] = HIDE_ALCOVES[ai]["pos"]
	for li in range(LURE_SPECS.size()):
		anchors["flure_%d" % li] = LURE_SPECS[li]["pos"]
	for b in _branches:
		anchors["branch_%d" % int(b["gap"])] = Vector3(float(b["mid_x"]), 0.5, float(b["pad_lane"]))
	return anchors

func get_preview_time_state() -> Dictionary:
	return {"day": 2, "time": 0.5, "routing_mode": "safe",
		"note_default": "Read the flood beat. Override the flush/jet, hold the plate for the bridge, time the current and the sluice."}

func get_preview_abilities() -> Array:
	return []

func get_preview_overlay_status(_overlay_id: String, _current_tick: float) -> Array:
	return []

func reset_preview_state() -> void:
	var n := SECTIONS.size()
	_phase = "ready"
	_override_locked = []; _flooding = []; _plate_held = []; _sluice_blocked = []; _flood_counts = []
	for i in range(n):
		_override_locked.append(false); _flooding.append(false); _plate_held.append(false); _sluice_blocked.append(false); _flood_counts.append(0)
	_washed.clear()
	_sloperope_deployed = false
	_branch_loot = 0
	for b in _branches:
		b["collected"] = false
		if is_instance_valid(b.get("cache")) and b["cache"].has_method("reset"):
			b["cache"].reset()
	if is_instance_valid(_rope_mesh):
		_rope_mesh.visible = false
	for i in range(_lure_until.size()):
		_lure_until[i] = -1.0
	var gs = _get_game_state()
	if gs != null:
		if gs.grid != null:
			for i in range(n):
				if str(SECTIONS[i]["type"]) == "sluice":
					for cell in _sluice_gate_cells(i):
						gs.grid.remove_dynamic_blocker(cell)
		for char_id in PARTY_IDS:
			if gs.characters.has(char_id):
				gs.snap_character_to(char_id, SPAWNS.get(char_id, START_POS))
				gs.set_character_concealment(char_id, GameState.CONCEAL_NONE)
		for enemy in _enemies:
			if is_instance_valid(enemy) and gs.characters.has(enemy.char_id):
				gs.set_character_distracted(enemy.char_id, false)
				gs.snap_character_to(enemy.char_id, _enemy_spawn_for(enemy.char_id))
	for i in range(_flow_strips.size()):
		_set_strip(i, 0.4)
	for i in range(_lure_meshes.size()):
		_set_lure_emission(i, 0.6)
	_set_preview_step("wash_relay_briefing")

func get_preview_state() -> Dictionary:
	var secs: Array = []
	for i in range(SECTIONS.size()):
		secs.append({"type": SECTIONS[i]["type"], "disable": SECTIONS[i]["disable"],
			"flooding": _flooding[i] if i < _flooding.size() else false,
			"disabled": _section_disabled(i), "overridden": _override_locked[i] if i < _override_locked.size() else false,
			"plate_held": _plate_held[i] if i < _plate_held.size() else false,
			"sluice_blocked": _sluice_blocked[i] if i < _sluice_blocked.size() else false,
			"period": _period(i), "flood_count": _flood_counts[i] if i < _flood_counts.size() else 0})
	var guards: Array = []
	var gs = _get_game_state()
	var branch_guard_count := 0
	# `guards` / `enemy_count` describe the SECTION threat layer; branch-offshoot guards are reported
	# separately (branch_guard_count + each branch's `guarded` flag) so the section semantics are stable.
	for enemy in _enemies:
		if not is_instance_valid(enemy):
			continue
		if _branch_guard_spawns.has(enemy.char_id):
			branch_guard_count += 1
			continue
		guards.append({
			"id": enemy.char_id, "alive": enemy.is_alive(),
			"state": (enemy.get_state() if enemy.has_method("get_state") else ""),
			"distracted": (gs != null and gs.is_character_distracted(enemy.char_id)),
		})
	var hidden_ids: Array = []
	if gs != null:
		for cid in PARTY_IDS:
			if gs.characters.has(cid) and gs.get_character_concealment(cid) >= GameState.CONCEAL_FULL:
				hidden_ids.append(cid)
	var branches: Array = []
	for b in _branches:
		branches.append({
			"gap": int(b["gap"]), "mid_x": float(b["mid_x"]), "pad_lane": float(b["pad_lane"]),
			"archetype": str(b["archetype"]), "content_count": int(b["content_count"]),
			"collected": bool(b.get("collected", false)),
			"guarded": is_instance_valid(b.get("guard")),
		})
	return {
		"phase": _phase, "complete": _phase == "complete",
		"sections": secs, "section_count": SECTIONS.size(),
		"washed_count": _washed.size(), "washed": _washed.keys(),
		"flow_period": FLOW_PERIOD, "flood_duration": FLOOD_DURATION,
		"enemy_count": guards.size(), "guards": guards,
		"lure_active": _lure_active(), "hidden": hidden_ids,
		"sloperope_deployed": _sloperope_deployed,
		"branches": branches, "branch_count": _branches.size(), "branch_loot": _branch_loot,
		"branch_guard_count": branch_guard_count,
	}
