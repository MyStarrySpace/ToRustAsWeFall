extends "res://scripts/scene_chunks/scene_chunk.gd"

## Two-lure relay puzzle. A long narrow hallway with an offshoot hiding spot near the far (second)
## lure. A group of enemies guards the exit (remains of a previous runner lie among them). Two
## ferrolures: Lure 1 near the ENTRANCE (far from the hide), Lure 2 near the ENEMIES (close to the hide).
##
## Intended solve: fire Lure 2 (the guards break toward it, clearing the path), duck into the nearby
## hiding spot, fire Lure 1 -> when Lure 2 expires the guards relay onward to Lure 1 (walking the whole
## hall back PAST the hidden party) -> slip out and run the now-open exit while Lure 1 holds them far away.
##
## The hide sits CLOSE to Lure 2 and FAR from Lure 1 on purpose: you can't just fire the near-entrance
## Lure 1 and hide straight away — the guards swarming to Lure 1 fill the only corridor to the hide, so
## you get spotted crossing. Only firing the far Lure 2 first clears that corridor. A navigation graph
## constrains everyone to the corridor (no diagonal dodge), so the data layer plays like the real scene.
##
## "Spotted = caught": a guard locking onto an exposed party member fails the run (so does a charge hit).
## Concealment is the shared GameState hidden flag, so headless runs the same puzzle as real play.

const EnemyScript := preload("res://scripts/game/ai/enemy.gd")

const PARTY_IDS := ["aster", "peris", "endo"]
const SPAWNS := {
	"aster": Vector3(5.0, 0.5, 0.0),
	"peris": Vector3(4.0, 0.5, 1.0),
	"endo": Vector3(4.0, 0.5, -1.0),
}

const HALL_CENTER := Vector3(31.0, -0.05, 0.0)
const HALL_SIZE := Vector3(66.0, 0.1, 5.0)   # world x in [-2, 64]
const HALL_HALF_Z := 2.0                     # walkable half-width of the hallway
const OFFSHOOT_CENTER := Vector3(34.0, -0.05, -5.0)
const OFFSHOOT_SIZE := Vector3(5.0, 0.1, 6.0) # world z in [-8, -2]

const LURE1_POS := Vector3(10.0, 0.5, 0.0)   # first / near the entrance — FAR from the hide
const LURE2_POS := Vector3(40.0, 0.5, 0.0)   # second / near the enemies — CLOSE to the hide
const HIDE_POS := Vector3(34.0, 0.5, -5.0)
const HIDE_RADIUS := 2.4
const EXIT_X := 60.0
const GUARD_POSITIONS := [Vector3(50.0, 0.5, 0.0), Vector3(51.2, 0.5, 1.2), Vector3(51.2, 0.5, -1.2)]
const CORPSE_POS := Vector3(51.0, 0.0, 0.0)
const LURE_DURATION := 12.0       # scheduler ticks a guard stays drawn to a lure
const LURE_TEND_TIME := 2.5       # Peris tends a ferrolure (after walking to it) before it sings out
const GUARD_SPEED := 4.5          # between a character's walk (~3.0) and run (6.0): threatening, escapable

var _enemies: Array = []
var _phase := "ready"             # ready | active | complete | failed
var _failure_reason := ""
var _lure1_until := -1.0          # scheduler tick a lure stops drawing (<=0 = inactive)
var _lure2_until := -1.0
var _committed_lure := 0          # which lure the enemies are currently walking to (0 = none)
var _lure1_mesh: MeshInstance3D
var _lure2_mesh: MeshInstance3D

# --- Build ---

func _build_chunk() -> void:
	_add_floor(self, HALL_CENTER, HALL_SIZE, Color(0.09, 0.1, 0.12))
	_add_floor(self, OFFSHOOT_CENTER, OFFSHOOT_SIZE, Color(0.08, 0.11, 0.1))
	_build_walls()
	_lure1_mesh = _build_lure_visual("Lure1", LURE1_POS)
	_lure2_mesh = _build_lure_visual("Lure2", LURE2_POS)
	_build_corpse()
	_add_label(self, "HIDE", HIDE_POS + Vector3(0.0, 1.6, 0.0), Color(0.5, 0.85, 0.7))
	_add_light(self, HIDE_POS + Vector3(0.0, 1.2, 0.0), Color(0.3, 0.6, 0.5), 0.7, 3.0)
	_add_light(self, Vector3(EXIT_X - 2.0, 1.5, 0.0), Color(0.8, 0.75, 0.6), 1.1, 5.0)
	_build_interactables()
	_spawn_guards()

func _build_walls() -> void:
	var wc := Color(0.06, 0.06, 0.08)
	var north_z := HALL_HALF_Z + 0.2
	var south_z := -HALL_HALF_Z - 0.2
	var min_x := HALL_CENTER.x - HALL_SIZE.x / 2.0
	var max_x := HALL_CENTER.x + HALL_SIZE.x / 2.0
	# North wall, solid the full length.
	_add_box(self, Vector3(HALL_CENTER.x, 1.4, north_z), Vector3(HALL_SIZE.x, 2.8, 0.3), wc)
	# South wall, broken by the offshoot mouth (a gap around the hide's x).
	var gap_min := OFFSHOOT_CENTER.x - OFFSHOOT_SIZE.x / 2.0
	var gap_max := OFFSHOOT_CENTER.x + OFFSHOOT_SIZE.x / 2.0
	var left_len := gap_min - min_x
	var right_len := max_x - gap_max
	_add_box(self, Vector3(min_x + left_len / 2.0, 1.4, south_z), Vector3(left_len, 2.8, 0.3), wc)
	_add_box(self, Vector3(gap_max + right_len / 2.0, 1.4, south_z), Vector3(right_len, 2.8, 0.3), wc)
	# Offshoot pocket walls (around the hide spot).
	var off_back_z := OFFSHOOT_CENTER.z - OFFSHOOT_SIZE.z / 2.0
	_add_box(self, Vector3(gap_min - 0.15, 1.4, OFFSHOOT_CENTER.z), Vector3(0.3, 2.8, OFFSHOOT_SIZE.z), wc)
	_add_box(self, Vector3(gap_max + 0.15, 1.4, OFFSHOOT_CENTER.z), Vector3(0.3, 2.8, OFFSHOOT_SIZE.z), wc)
	_add_box(self, Vector3(OFFSHOOT_CENTER.x, 1.4, off_back_z - 0.15), Vector3(OFFSHOOT_SIZE.x, 2.8, 0.3), wc)

func _build_lure_visual(node_name: String, pos: Vector3) -> MeshInstance3D:
	var mesh := _add_box(self, pos, Vector3(0.4, 0.4, 0.4), Color(0.7, 0.45, 0.15),
		Color(0.8, 0.4, 0.1), 0.5, node_name + "Mesh")
	return mesh

func _build_corpse() -> void:
	# Remains of a previous runner, slumped among the guards.
	_add_box(self, CORPSE_POS + Vector3(0.0, 0.12, 0.0), Vector3(1.4, 0.24, 0.5),
		Color(0.18, 0.14, 0.12), Color.BLACK, 0.0, "Remains")
	_add_label(self, "remains", CORPSE_POS + Vector3(0.0, 0.6, 0.0), Color(0.55, 0.4, 0.38))

# The lures are TIMED_ACTION interactables (CLICK to use, never proximity): with Peris active, a click
# walks her over, then she TENDS it for LURE_TEND_TIME (the interactable's own dwell timer, with the
# progress ring) before `interacted` fires and the lure sings. The tend duration is the interactable's
# dwell_time, not a hand-rolled per-chunk schedule, so terminals and other "takes time" interactables
# reuse the same type. (Tests still drive activate_lure1/2 directly for the immediate state change.)
func _build_interactables() -> void:
	var lure2 := _add_interactable(self, "Lure2Interact", "Ferrolure", LURE2_POS,
		"Tend", "peris", LURE_TEND_TIME, true, 1.6, Interactable.InteractableType.TIMED_ACTION)
	lure2.interacted.connect(func() -> void: activate_lure2())
	var lure1 := _add_interactable(self, "Lure1Interact", "Ferrolure", LURE1_POS,
		"Tend", "peris", LURE_TEND_TIME, true, 1.6, Interactable.InteractableType.TIMED_ACTION)
	lure1.interacted.connect(func() -> void: activate_lure1())

func _spawn_guards() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	for i in range(GUARD_POSITIONS.size()):
		var enemy := EnemyScript.new()
		enemy.name = "RelayGuard%d" % i
		enemy.position = GUARD_POSITIONS[i]
		enemy.move_speed = GUARD_SPEED
		enemy.detection_range = 5.0
		enemy._detection_targets.assign(PARTY_IDS)
		add_child(enemy)
		_register_enemy(enemy, "relay_guard_%d" % i, enemy.move_speed)
		# GUARDING = idle in place (no patrol → no roaming pathfinding); they only pathfind to chase.
		enemy.hit_target.connect(_on_guard_hit)
		enemy.target_spotted.connect(_on_guard_spotted)
		_enemies.append(enemy)

func _register_enemy(enemy, id: String, speed: float) -> void:
	var gs = _get_game_state()
	if gs == null or enemy == null:
		return
	enemy.char_id = id
	enemy.game_state = gs
	gs.register_character(id, enemy.position, speed, {"detection_range": float(enemy.detection_range)})
	if enemy.has_method("activate"):
		enemy.activate()

## Constrain everyone to the corridor + offshoot: a centerline of waypoints down the hall, with a branch
## into the hiding spot. Movement (player AND guards) routes along these, so there's no diagonal cut to
## the hide — the only path crosses the hall, which is what makes firing Lure 1 alone get you spotted.
func get_navigation_graph_data() -> Dictionary:
	var nodes: Array = []
	var edges: Array = []
	var xs := [4, 10, 16, 22, 28, 34, 40, 46, 52, 58, 62]
	var prev := ""
	for x in xs:
		var nid := "c%d" % x
		nodes.append({"id": nid, "position": [float(x), 0.5, 0.0]})
		if prev != "":
			edges.append({"from": prev, "to": nid, "bidirectional": true})
		prev = nid
	# Offshoot branch off the corridor node nearest the hide's x.
	nodes.append({"id": "hide", "position": [HIDE_POS.x, 0.5, HIDE_POS.z]})
	edges.append({"from": "c34", "to": "hide", "bidirectional": true})
	return {
		"entry_node": "c4",
		"exit_node": "c62",
		"max_snap_distance": 9.0,
		"nodes": nodes,
		"edges": edges,
	}

# --- Lure relay ---

func activate_lure2() -> bool:
	return _activate_lure(2)

func activate_lure1() -> bool:
	return _activate_lure(1)

func _activate_lure(which: int) -> bool:
	if _phase in ["complete", "failed"]:
		return false
	_phase = "active"
	var now := _get_scheduler_tick()
	if which == 2:
		_lure2_until = now + LURE_DURATION
		_set_lure_emission(_lure2_mesh, 3.0)
	else:
		_lure1_until = now + LURE_DURATION
		_set_lure_emission(_lure1_mesh, 3.0)
	# Only seize the enemies if they aren't already committed to a lure (the puzzle relies on Lure 2
	# holding them until it expires, THEN relaying to Lure 1).
	if _committed_lure == 0:
		_commit_enemies_to(which)
	var sched = _get_scheduler()
	if sched != null:
		sched.schedule_after(LURE_DURATION, func() -> void: _on_lure_expired(which), "lure_relay_%d" % which)
	_show_message("Ferrolure %d sings out." % which, 1.4)
	_set_preview_step("lure_relay_active")
	return true

func _commit_enemies_to(which: int) -> void:
	_committed_lure = which
	# The committed lure draws for a FULL window from now — a relay resets it, so the runner gets a
	# clean window to move while the sentries are occupied (not the ~1-tick scrap left on the timer).
	var now := _get_scheduler_tick()
	var sched = _get_scheduler()
	if which == 2:
		_lure2_until = now + LURE_DURATION
	else:
		_lure1_until = now + LURE_DURATION
	if sched != null:
		sched.cancel_tag("lure_relay_%d" % which)
		sched.schedule_after(LURE_DURATION, func() -> void: _on_lure_expired(which), "lure_relay_%d" % which)
	var pos: Vector3 = LURE2_POS if which == 2 else LURE1_POS
	var gs = _get_game_state()
	for i in range(_enemies.size()):
		var enemy = _enemies[i]
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		# Drop the hunt and walk to the lure (one direct move; idle on arrival). Deterministic fan
		# offset (no wall-clock RNG) so the data layer runs the same puzzle headless. The guard stays
		# alert to the party but DISTRACTED — its reach shrinks, so it won't notice a runner keeping
		# distance, yet still catches one who steps right into it. Hide as it passes; don't crowd it.
		enemy._current_target_id = ""
		if enemy.has_method("_change_state"):
			enemy._change_state("idle")
		if gs != null and gs.characters.has(enemy.char_id):
			gs.set_character_distracted(enemy.char_id, true)
			gs.command_move_to_pos(enemy.char_id, pos + Vector3(0.0, 0.0, float(i - 1) * 0.7))

func _on_lure_expired(which: int) -> void:
	if which == 2:
		_lure2_until = -1.0
		_set_lure_emission(_lure2_mesh, 0.5)
	else:
		_lure1_until = -1.0
		_set_lure_emission(_lure1_mesh, 0.5)
	if _committed_lure != which:
		return
	var now := _get_scheduler_tick()
	# Relay: if the OTHER lure is still singing, the enemies move on to it; otherwise they give up
	# and return to guarding (detection re-armed).
	if which == 2 and _lure1_until > now:
		_commit_enemies_to(1)
	elif which == 1 and _lure2_until > now:
		_commit_enemies_to(2)
	else:
		_committed_lure = 0
		_release_enemies()

func _release_enemies() -> void:
	var gs = _get_game_state()
	for enemy in _enemies:
		if is_instance_valid(enemy) and enemy.is_alive():
			enemy._detection_targets.assign(PARTY_IDS)
			if gs != null and gs.characters.has(enemy.char_id):
				gs.set_character_distracted(enemy.char_id, false)
				gs.command_move_to_pos(enemy.char_id, _guard_post_for(enemy.char_id))
			if enemy.has_method("_change_state"):
				enemy._change_state("idle")

## The home post a guard returns to when it gives up a lure (its spawn slot).
func _guard_post_for(char_id: String) -> Vector3:
	for i in range(_enemies.size()):
		if is_instance_valid(_enemies[i]) and _enemies[i].char_id == char_id:
			return GUARD_POSITIONS[i]
	return GUARD_POSITIONS[0]

func _set_lure_emission(mesh: MeshInstance3D, energy: float) -> void:
	if mesh != null and mesh.material_override is StandardMaterial3D:
		(mesh.material_override as StandardMaterial3D).emission_energy_multiplier = energy

# --- Per-frame ---

func _process(delta: float) -> void:
	_update(delta)

func headless_process(delta: float) -> void:
	_update(delta)

func _update(_delta: float) -> void:
	if _phase in ["complete", "failed"]:
		return
	var gs = _get_game_state()
	if gs == null:
		return
	# Concealment: each party member tucked in the offshoot is hidden from detection.
	for char_id in PARTY_IDS:
		if not gs.characters.has(char_id):
			continue
		var pos := _get_character_position(char_id)
		var in_hide := Vector2(pos.x - HIDE_POS.x, pos.z - HIDE_POS.z).length() <= HIDE_RADIUS
		gs.set_character_hidden(char_id, in_hide)
	# Win: the lead character clears the exit threshold.
	if _phase == "active" and _get_character_position(_get_active_character()).x >= EXIT_X:
		_complete()

func _on_guard_spotted(target_id: String) -> void:
	# A sentry locking onto an exposed party member ends the run — this is the stealth fail that makes
	# firing Lure 1 alone (then crossing the swarmed corridor to the distant hide) a loss.
	if _phase in ["complete", "failed"]:
		return
	if not (target_id in PARTY_IDS):
		return
	_phase = "failed"
	_failure_reason = "spotted"
	_show_note("A sentry's eye locks on. Caught.", 2.5)
	_set_preview_step("lure_relay_failed")

func _on_guard_hit(_target_id: String, _damage: float) -> void:
	if _phase in ["complete", "failed"]:
		return
	_phase = "failed"
	_failure_reason = "caught"
	_show_note("A sentry ran you down. The remains gain a companion.", 2.5)
	_set_preview_step("lure_relay_failed")

func _complete() -> void:
	_phase = "complete"
	_show_note("Past the sentries while the lure held. The exit is yours.", 2.5)
	_set_preview_step("lure_relay_complete")

# --- SceneChunk interface ---

func get_scene_title() -> String:
	return "Ferrolure Relay"

func get_scene_help() -> String:
	return "Fire the far lure to clear the path, hide by it, then fire the near one — let the sentries relay past you and run the exit."

func get_default_character() -> String:
	return "peris"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate(true)

func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors.merge({
		"lure_one": LURE1_POS,
		"lure_two": LURE2_POS,
		"hide_spot": HIDE_POS,
		"exit": Vector3(EXIT_X + 1.0, 0.5, 0.0),
		"guards": GUARD_POSITIONS[0],
	}, true)
	return anchors

func get_preview_time_state() -> Dictionary:
	return {
		"day": 2,
		"time": 0.62,
		"routing_mode": "safe",
		"note_default": "Two lures, one hiding spot, a guarded exit. Time the relay.",
	}

func get_preview_abilities() -> Array:
	return []

func get_preview_overlay_status(_overlay_id: String, _current_tick: float) -> Array:
	return []

func reset_preview_state() -> void:
	_phase = "ready"
	_failure_reason = ""
	_lure1_until = -1.0
	_lure2_until = -1.0
	_committed_lure = 0
	_set_lure_emission(_lure1_mesh, 0.5)
	_set_lure_emission(_lure2_mesh, 0.5)
	_release_enemies()
	var gs = _get_game_state()
	if gs != null:
		for char_id in PARTY_IDS:
			if gs.characters.has(char_id):
				gs.set_character_hidden(char_id, false)
				gs.set_character_distracted(char_id, false)
	_set_preview_step("lure_relay_briefing")

func get_preview_state() -> Dictionary:
	var now := _get_scheduler_tick()
	return {
		"phase": _phase,
		"failure_reason": _failure_reason,
		"lure1_active": _lure1_until > now,
		"lure2_active": _lure2_until > now,
		"committed_lure": _committed_lure,
		"complete": _phase == "complete",
		"failed": _phase == "failed",
	}
