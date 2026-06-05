extends "res://scripts/scene_chunks/scene_chunk.gd"

## Two-lure relay puzzle. A narrow hallway with an offshoot hiding spot. A group of enemies guards
## the exit (remains of a previous runner lie between them). Two ferrolures: Lure 1 near the entrance,
## Lure 2 near the enemies, the hiding spot between them.
##
## Intended solve: fire Lure 2 (the enemies break toward it) -> fire Lure 1 -> duck into the hiding
## spot BEFORE Lure 2 expires -> when Lure 2 expires the enemies, still drawn, relay onward to Lure 1
## (walking back PAST the hidden party) -> slip out and run the now-open exit while Lure 1 holds.
##
## Enemies that GUARD just idle at the exit (no patrol pathfinding — roaming shouldn't pathfind); a
## lure sends them on one direct move; only an actual sighting makes them pursue (the chase pathfinds).
## Concealment is the shared GameState hidden flag, so the data layer runs the same puzzle headless.

const EnemyScript := preload("res://scripts/game/ai/enemy.gd")

const PARTY_IDS := ["aster", "peris", "endo"]
const SPAWNS := {
	"aster": Vector3(4.0, 0.5, 0.0),
	"peris": Vector3(3.0, 0.5, 1.0),
	"endo": Vector3(3.0, 0.5, -1.0),
}

const HALL_CENTER := Vector3(21.0, -0.05, 0.0)
const HALL_SIZE := Vector3(46.0, 0.1, 5.0)
const HALL_HALF_Z := 2.0          # walkable half-width of the hallway
const OFFSHOOT_CENTER := Vector3(20.0, -0.05, -4.5)
const OFFSHOOT_SIZE := Vector3(5.0, 0.1, 5.0)

const LURE1_POS := Vector3(11.0, 0.5, 0.0)
const LURE2_POS := Vector3(29.0, 0.5, 0.0)
const HIDE_POS := Vector3(20.0, 0.5, -4.5)
const HIDE_RADIUS := 2.2
const EXIT_X := 42.0
const GUARD_POSITIONS := [Vector3(35.0, 0.5, 0.0), Vector3(36.2, 0.5, 1.2), Vector3(36.2, 0.5, -1.2)]
const CORPSE_POS := Vector3(35.5, 0.0, 0.0)
const LURE_DURATION := 8.0        # scheduler ticks an enemy stays drawn to a lure

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
	# North wall, solid.
	_add_box(self, Vector3(HALL_CENTER.x, 1.4, HALL_HALF_Z + 0.2), Vector3(HALL_SIZE.x, 2.8, 0.3), wc)
	# South wall, with a gap where the offshoot opens (x in [17.5, 22.5]).
	_add_box(self, Vector3(9.0, 1.4, -HALL_HALF_Z - 0.2), Vector3(18.0, 2.8, 0.3), wc)
	_add_box(self, Vector3(32.5, 1.4, -HALL_HALF_Z - 0.2), Vector3(19.0, 2.8, 0.3), wc)
	# Offshoot pocket walls (around the hide spot).
	_add_box(self, Vector3(17.7, 1.4, -4.5), Vector3(0.3, 2.8, 5.0), wc)
	_add_box(self, Vector3(22.3, 1.4, -4.5), Vector3(0.3, 2.8, 5.0), wc)
	_add_box(self, Vector3(20.0, 1.4, -7.0), Vector3(5.0, 2.8, 0.3), wc)
	# Back wall behind the guards (the exit is the gap at the far +x end).
	_add_box(self, Vector3(HALL_CENTER.x, 1.4, HALL_HALF_Z + 0.2), Vector3(0.0, 0.0, 0.0), wc)

func _build_lure_visual(node_name: String, pos: Vector3) -> MeshInstance3D:
	var mesh := _add_box(self, pos, Vector3(0.4, 0.4, 0.4), Color(0.7, 0.45, 0.15),
		Color(0.8, 0.4, 0.1), 0.5, node_name + "Mesh")
	return mesh

func _build_corpse() -> void:
	# Remains of a previous runner, slumped between the guards.
	_add_box(self, CORPSE_POS + Vector3(0.0, 0.12, 0.0), Vector3(1.4, 0.24, 0.5),
		Color(0.18, 0.14, 0.12), Color.BLACK, 0.0, "Remains")
	_add_label(self, "remains", CORPSE_POS + Vector3(0.0, 0.6, 0.0), Color(0.55, 0.4, 0.38))

func _build_interactables() -> void:
	var lure2 := _add_interactable(self, "Lure2Interact", "Ferrolure", LURE2_POS,
		"Lure", "peris", 0.6, true, 1.6)
	lure2.interacted.connect(func() -> void: activate_lure2())
	var lure1 := _add_interactable(self, "Lure1Interact", "Ferrolure", LURE1_POS,
		"Lure", "peris", 0.6, true, 1.6)
	lure1.interacted.connect(func() -> void: activate_lure1())

func _spawn_guards() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	for i in range(GUARD_POSITIONS.size()):
		var enemy := EnemyScript.new()
		enemy.name = "RelayGuard%d" % i
		enemy.position = GUARD_POSITIONS[i]
		enemy.move_speed = 1.7
		enemy.detection_range = 5.0
		enemy._detection_targets.assign(PARTY_IDS)
		add_child(enemy)
		_register_enemy(enemy, "relay_guard_%d" % i, enemy.move_speed)
		# GUARDING = idle in place (no patrol → no roaming pathfinding); they only pathfind to chase.
		enemy.hit_target.connect(_on_guard_hit)
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
			if enemy.has_method("_change_state"):
				enemy._change_state("idle")

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
	return "Fire the far lure, then the near one. Hide between them, let the sentries relay past you, then run the exit."

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
