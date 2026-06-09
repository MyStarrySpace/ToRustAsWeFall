extends "res://scripts/scene_chunks/scene_chunk.gd"

## Refuge Run — a composite shelter-to-shelter stretch that exercises all three
## canonical hiding types, both enemy types, benign + hazard flora, and a branching
## route choice:
##   - Concealment Patch (Hush Moss): a radius refuge that hides the active member.
##   - Hide Slit: a location refuge that only holds during an open lure window.
##   - Hide Spot: a party shelter that holds only while the whole party stays put
##     through a swarm sweep.
## The fork splits a safe NORTH route (around the standard enemy, past the moss)
## from a DIRECT SOUTH route (shorter, but a hazard bloom bleeds HP and a chain
## enemy works the tight seam). Both converge into the slit -> spot -> exit run.

const EnemyScript := preload("res://scripts/game/ai/enemy.gd")
const ChainEnemyScript := preload("res://scripts/game/ai/chain_enemy.gd")

const PARTY_IDS := ["aster", "peris", "endo"]

const FLOOR_CENTER := Vector3(35.0, -0.05, 0.0)
const FLOOR_SIZE := Vector3(76.0, 0.1, 28.0)

const ENTRY_SHELTER_POS := Vector3(6.0, 0.45, 0.0)
const HUSHBLOOM_POS := Vector3(10.0, 0.45, 3.4)
const FORK_POS := Vector3(16.0, 0.45, 0.0)
const NORTH_LANE_Z := -7.5
const SOUTH_LANE_Z := 7.5
const CONCEAL_PATCH_POS := Vector3(28.0, 0.45, NORTH_LANE_Z)
const RISKY_BLOOM_POS := Vector3(27.0, 0.45, SOUTH_LANE_Z)
const STANDARD_ENEMY_POS := Vector3(28.0, 0.5, 0.0)
const CHAIN_ENEMY_POS := Vector3(31.0, 0.5, SOUTH_LANE_Z)
const CONVERGE_POS := Vector3(41.0, 0.45, 0.0)
const HIDE_SLIT_POS := Vector3(49.0, 0.45, -3.2)
const HIDE_SPOT_POS := Vector3(59.0, 0.45, 0.0)
const EXIT_SHELTER_POS := Vector3(70.0, 0.45, 0.0)

const SHELTER_RADIUS := 2.8
const PATCH_RADIUS := 2.5
const STATION_RADIUS := 2.4
const SPOT_RADIUS := 3.4
const SLIT_WINDOW := 6.0
const SPOT_SWEEP := 6.0
const RISKY_BLOOM_DAMAGE := 22.0
const TEND_STAMINA := 10.0

const SPAWNS := {
	"aster": Vector3(7.4, 0.5, 1.4),
	"peris": Vector3(5.6, 0.5, 0.0),
	"endo": Vector3(6.2, 0.5, -1.6),
}

var _route_phase := "briefing"
var _route_choice := ""
var _last_outcome := ""
var _bloom_tended := false
var _hazard_taken := false
var _patch_concealed := false
var _slit_phase := "ready"
var _slit_window_until := -1.0
var _spot_phase := "ready"
var _spot_sweep_until := -1.0
var _shelter_reached := false

var _standard_enemy
var _chain_enemy
var _patch_material: StandardMaterial3D
var _slit_material: StandardMaterial3D
var _spot_material: StandardMaterial3D
var _hushbloom_material: StandardMaterial3D
var _risky_bloom_material: StandardMaterial3D
var _entry_beacon: StandardMaterial3D
var _exit_beacon: StandardMaterial3D

func _build_chunk() -> void:
	_add_floor(self, FLOOR_CENTER, FLOOR_SIZE, Color(0.085, 0.09, 0.11))
	_add_box(self, Vector3(35.0, 2.4, -14.1), Vector3(76.0, 4.8, 0.3), Color(0.13, 0.14, 0.16))
	_add_box(self, Vector3(35.0, 2.4, 14.1), Vector3(76.0, 4.8, 0.3), Color(0.13, 0.14, 0.16))
	for i in range(8):
		var blend := float(i) / 7.0
		_add_light(self, Vector3(6.0 + float(i) * 9.0, 3.4, 0.0),
			Color(0.26 + blend * 0.2, 0.3 + blend * 0.14, 0.4 - blend * 0.1), 1.1 + blend * 1.1, 13.0)

	_entry_beacon = _add_marker(ENTRY_SHELTER_POS, Vector3(2.4, 0.5, 2.4), Color(0.2, 0.5, 0.7), 1.6, "ENTRY")
	_exit_beacon = _add_marker(EXIT_SHELTER_POS, Vector3(2.4, 0.5, 2.4), Color(0.3, 0.7, 0.45), 1.6, "EXIT")
	_add_label(self, "FORK", FORK_POS + Vector3(0, 2.2, 0))

	# North (safe) lane + concealment patch (hush moss).
	_add_box(self, Vector3(28.0, -0.04, NORTH_LANE_Z), Vector3(26.0, 0.06, 5.0), Color(0.1, 0.12, 0.1))
	_patch_material = _make_material(Color(0.16, 0.3, 0.16), Color(0.3, 0.85, 0.4), 0.5)
	var patch := _add_box(self, CONCEAL_PATCH_POS - Vector3(0, 0.42, 0), Vector3(PATCH_RADIUS * 2.0, 0.08, PATCH_RADIUS * 2.0), Color(0.16, 0.3, 0.16))
	patch.material_override = _patch_material
	_add_label(self, "HUSH MOSS", CONCEAL_PATCH_POS + Vector3(0, 1.8, 0), Color(0.5, 0.9, 0.6))

	# South (direct) lane + hazard bloom.
	_add_box(self, Vector3(28.0, -0.04, SOUTH_LANE_Z), Vector3(26.0, 0.06, 5.0), Color(0.12, 0.1, 0.1))
	_risky_bloom_material = _make_material(Color(0.32, 0.14, 0.1), Color(0.95, 0.32, 0.12), 0.6)
	_add_flora(RISKY_BLOOM_POS, _risky_bloom_material, 0.7)
	_add_label(self, "RUST BLOOM", RISKY_BLOOM_POS + Vector3(0, 1.8, 0), Color(0.95, 0.5, 0.35))

	# Benign hushbloom near entry (tend for stamina).
	_hushbloom_material = _make_material(Color(0.2, 0.26, 0.34), Color(0.45, 0.6, 0.95), 0.4)
	_add_flora(HUSHBLOOM_POS, _hushbloom_material, 0.55)
	_add_label(self, "HUSHBLOOM", HUSHBLOOM_POS + Vector3(0, 1.6, 0), Color(0.6, 0.75, 1.0))

	# Hide slit (location + window).
	_slit_material = _make_material(Color(0.2, 0.2, 0.3), Color(0.4, 0.45, 0.85), 0.35)
	var slit := _add_box(self, HIDE_SLIT_POS - Vector3(0, 0.42, 0), Vector3(STATION_RADIUS * 2.0, 0.08, STATION_RADIUS * 2.0), Color(0.2, 0.2, 0.3))
	slit.material_override = _slit_material
	_add_label(self, "SLIT", HIDE_SLIT_POS + Vector3(0, 1.8, 0), Color(0.6, 0.65, 1.0))

	# Hide spot (party shelter).
	_spot_material = _make_material(Color(0.22, 0.24, 0.2), Color(0.55, 0.7, 0.4), 0.35)
	var spot := _add_box(self, HIDE_SPOT_POS - Vector3(0, 0.42, 0), Vector3(SPOT_RADIUS * 2.0, 0.08, SPOT_RADIUS * 2.0), Color(0.22, 0.24, 0.2))
	spot.material_override = _spot_material
	_add_label(self, "SHELTER SPOT", HIDE_SPOT_POS + Vector3(0, 1.9, 0), Color(0.7, 0.9, 0.55))

	_spawn_enemies()
	_update_visual_state()
	_set_preview_step("refuge_run_briefing")

func _process(delta: float) -> void:
	_update(delta)

func headless_process(delta: float) -> void:
	_update(delta)

# --- Scene metadata ---

func get_scene_title() -> String:
	return "Refuge Run"

func get_scene_help() -> String:
	return "Pick the fork, slip the standard sentry with the hush moss (or burn the rust bloom on the direct seam past the chain), cross the slit while its window is open, hold the whole party in the shelter spot through the sweep, then reach the exit shelter."

func get_default_character() -> String:
	return "aster"

func get_spawn_positions() -> Dictionary:
	return SPAWNS.duplicate(true)

func get_preview_anchors() -> Dictionary:
	var anchors := get_spawn_positions()
	anchors.merge({
		"entry_shelter": ENTRY_SHELTER_POS,
		"hushbloom": HUSHBLOOM_POS,
		"fork": FORK_POS,
		"conceal_patch": CONCEAL_PATCH_POS,
		"risky_bloom": RISKY_BLOOM_POS,
		"standard_sentry": STANDARD_ENEMY_POS,
		"chain_seam": CHAIN_ENEMY_POS,
		"converge": CONVERGE_POS,
		"hide_slit": HIDE_SLIT_POS,
		"hide_spot": HIDE_SPOT_POS,
		"exit_shelter": EXIT_SHELTER_POS,
	}, true)
	return anchors

func get_preview_time_state() -> Dictionary:
	return {
		"day": 4,
		"time": 0.62,
		"routing_mode": "safe",
		"note_default": "A full expedition slice: the team is healthy, all three hiding types and both sentries are live, and the run only completes if the slit window, the shelter-spot sweep, and the chosen route all line up cleanly.",
	}

func get_preview_abilities() -> Array:
	# Display names + descriptions + tuning live in data/abilities/en/abilities.xlsx (per-context rows).
	return AbilityData.for_context("refuge_run")
func get_preview_state() -> Dictionary:
	return {
		"route_phase": _route_phase,
		"route_choice": _route_choice,
		"last_outcome": _last_outcome,
		"bloom_tended": _bloom_tended,
		"hazard_taken": _hazard_taken,
		"patch_concealed": _patch_concealed,
		"slit_phase": _slit_phase,
		"slit_window_open": _slit_window_until > 0.0,
		"spot_phase": _spot_phase,
		"spot_sweep_active": _spot_sweep_until > 0.0,
		"shelter_reached": _shelter_reached,
		"hiding_type_count": 3,
		"enemy_count": _enemy_count(),
		"plant_count": 2,
		"route_count": 2,
		"enemy": {
			"standard": _enemy_report(_standard_enemy),
			"chain": _enemy_report(_chain_enemy),
		},
	}

func get_preview_overlay_status(overlay_id: String, _current_tick: float) -> Array:
	match overlay_id:
		"aster":
			return ["DATA: fork splits safe-north / direct-south.", "Route: %s" % (_route_choice if _route_choice != "" else "unset")]
		"peris":
			return ["FOG: the hush moss reads cool; the rust bloom reeks of iron.", "Bloom tended: %s" % ("yes" if _bloom_tended else "no")]
		"endo":
			return ["Seam: the slit only holds while the lure window is open.", "Shelter spot needs the whole party."]
	return []

# --- Public chunk methods (driven by scenarios / play) ---

func reset_preview_state() -> void:
	_route_phase = "briefing"
	_route_choice = ""
	_last_outcome = ""
	_bloom_tended = false
	_hazard_taken = false
	_patch_concealed = false
	_slit_phase = "ready"
	_slit_window_until = -1.0
	_spot_phase = "ready"
	_spot_sweep_until = -1.0
	_shelter_reached = false
	_update_visual_state()
	_set_preview_step("refuge_run_briefing")

## Lock in the fork choice. The direct south route bleeds HP through the rust bloom.
func choose_route(route_id: String) -> bool:
	if _route_phase in ["failed", "complete"]:
		return false
	if route_id != "north" and route_id != "south":
		_last_outcome = "bad_route:%s" % route_id
		return false
	_route_choice = route_id
	_route_phase = "underway"
	if route_id == "south" and not _hazard_taken:
		_hazard_taken = true
		for char_id in PARTY_IDS:
			_adjust_character_stat(char_id, "hp", -RISKY_BLOOM_DAMAGE)
		_last_outcome = "burned_rust_bloom"
		_show_message("The direct seam burns through the rust bloom.", 1.6)
	else:
		_last_outcome = "route:%s" % route_id
		_show_message("Holding to the safe north lane.", 1.6)
	_set_preview_step("refuge_run_%s" % route_id)
	return true

## Peris tends the hushbloom for a small stamina buffer (no-op away from it).
func tend_bloom() -> bool:
	if _bloom_tended:
		return false
	if not _active_in_radius(HUSHBLOOM_POS, STATION_RADIUS):
		_last_outcome = "tend_too_far"
		return false
	_bloom_tended = true
	_adjust_character_stat(_get_active_character(), "stamina", TEND_STAMINA)
	_last_outcome = "bloom_tended"
	_show_message("The hushbloom settles the party.", 1.4)
	return true

## Open the slit's lure window. The active member must reach the slit before it closes.
func activate_slit_lure() -> bool:
	if _route_phase in ["failed", "complete"]:
		return false
	if _slit_phase in ["safe", "failed"]:
		return false
	_slit_window_until = _get_scheduler_tick() + SLIT_WINDOW
	if _slit_phase == "ready":
		_slit_phase = "ready"
	_last_outcome = "slit_window_open"
	_set_preview_step("refuge_run_slit")
	_show_message("The slit's lure window is open.", 1.4)
	return true

## Start the shelter-spot sweep. The whole party must hold the spot until it passes.
func activate_spot_sweep() -> bool:
	if _route_phase in ["failed", "complete"]:
		return false
	if _spot_phase in ["safe", "failed"]:
		return false
	_spot_sweep_until = _get_scheduler_tick() + SPOT_SWEEP
	_last_outcome = "spot_sweep_active"
	_set_preview_step("refuge_run_spot")
	_show_message("A sweep rolls through — hold the shelter spot.", 1.4)
	return true

## Reach the exit shelter. Only completes once both timed refuges are cleared.
func reach_exit() -> bool:
	if _route_phase in ["failed", "complete"]:
		return false
	if not _all_party_in_radius(EXIT_SHELTER_POS, SHELTER_RADIUS):
		_last_outcome = "exit_party_not_gathered"
		return false
	if _slit_phase != "safe" or _spot_phase != "safe":
		_last_outcome = "exit_refuges_incomplete"
		return false
	_shelter_reached = true
	_route_phase = "complete"
	_last_outcome = "success"
	_set_preview_step("refuge_run_complete")
	_show_note("Exit shelter reached — the stretch is crossed.", 2.5)
	return true

# --- Per-frame state machine (deterministic, scheduler-tick driven) ---

func _update(_delta: float) -> void:
	_patch_concealed = _route_phase not in ["failed", "complete"] and _active_in_radius(CONCEAL_PATCH_POS, PATCH_RADIUS)
	_update_slit()
	_update_spot()
	_update_visual_state()

func _update_slit() -> void:
	if _slit_window_until <= 0.0:
		return
	var tick := _get_scheduler_tick()
	if _slit_phase == "ready" and _active_in_radius(HIDE_SLIT_POS, STATION_RADIUS):
		_slit_phase = "hidden"
		_show_message("Tucked into the slit.", 1.0)
	if tick >= _slit_window_until:
		_slit_window_until = -1.0
		if _slit_phase == "hidden":
			_slit_phase = "safe"
			_show_message("The lane reopens — clear of the slit.", 1.2)
		elif _slit_phase == "ready":
			_slit_phase = "failed"
			_fail("slit_window_closed")

func _update_spot() -> void:
	if _spot_sweep_until <= 0.0:
		return
	var tick := _get_scheduler_tick()
	var party_in := _all_party_in_radius(HIDE_SPOT_POS, SPOT_RADIUS)
	if _spot_phase == "ready" and party_in:
		_spot_phase = "hidden"
		_show_message("The party folds into the shelter spot.", 1.0)
	elif _spot_phase == "hidden" and not party_in:
		_spot_sweep_until = -1.0
		_spot_phase = "failed"
		_fail("spot_exposed")
		return
	if tick >= _spot_sweep_until:
		_spot_sweep_until = -1.0
		if _spot_phase == "hidden":
			_spot_phase = "safe"
			_show_message("The sweep passes — the spot held.", 1.2)
		else:
			_spot_phase = "failed"
			_fail("spot_exposed")

func _fail(reason: String) -> void:
	_route_phase = "failed"
	_last_outcome = reason
	_set_preview_step("refuge_run_failed")

# --- Enemies ---

func _spawn_enemies() -> void:
	var gs = _get_game_state()
	if gs == null:
		return
	_standard_enemy = EnemyScript.new()
	_standard_enemy.name = "RefugeStandardSentry"
	_standard_enemy.position = STANDARD_ENEMY_POS
	_standard_enemy.move_speed = 1.6
	_standard_enemy.detection_range = 5.0
	_standard_enemy._detection_targets.assign(PARTY_IDS)
	add_child(_standard_enemy)
	_register_enemy(_standard_enemy, "refuge_standard", _standard_enemy.move_speed)
	if _standard_enemy.has_method("set_patrol"):
		var standard_patrol: Array[Vector3] = [Vector3(24.0, 0.0, 0.0), Vector3(34.0, 0.0, 0.0)]
		_standard_enemy.set_patrol(standard_patrol)

	_chain_enemy = ChainEnemyScript.new()
	_chain_enemy.name = "RefugeChainSeam"
	_chain_enemy.position = CHAIN_ENEMY_POS
	_chain_enemy.move_speed = 1.5
	_chain_enemy.detection_range = 5.0
	_chain_enemy._detection_targets.assign(PARTY_IDS)
	add_child(_chain_enemy)
	_register_enemy(_chain_enemy, "refuge_chain", _chain_enemy.move_speed)
	if _chain_enemy.has_method("set_wall_line"):
		_chain_enemy.set_wall_line(Vector3(31.0, 0.5, 12.0), Vector3(0, 0, -1))
	if _chain_enemy.has_method("set_patrol"):
		var chain_patrol: Array[Vector3] = [Vector3(28.0, 0.0, SOUTH_LANE_Z), Vector3(34.0, 0.0, SOUTH_LANE_Z)]
		_chain_enemy.set_patrol(chain_patrol)

## Replicates the host's _register_gs_character: register in GameState + wire the
## node. Enemy reads its scheduler from game_state.scheduler, so no extra wiring.
func _register_enemy(enemy, id: String, speed: float) -> void:
	var gs = _get_game_state()
	if gs == null or enemy == null:
		return
	enemy.char_id = id
	enemy.game_state = gs
	gs.register_character(id, enemy.position, speed, {"detection_range": float(enemy.detection_range)})
	if enemy.has_method("activate"):
		enemy.activate()

func _enemy_report(enemy) -> Dictionary:
	if enemy == null or not is_instance_valid(enemy):
		return {"state": "", "target": "", "distance_to_target": -1.0}
	var state := str(enemy.get_state()) if enemy.has_method("get_state") else ""
	var target := str(enemy._current_target_id)
	var dist := -1.0
	var gs = _get_game_state()
	if gs != null and target != "" and gs.characters.has(target):
		dist = gs.get_position(enemy.char_id).distance_to(gs.get_position(target))
	return {"state": state, "target": target, "distance_to_target": dist}

func _enemy_count() -> int:
	var n := 0
	if _standard_enemy != null and is_instance_valid(_standard_enemy):
		n += 1
	if _chain_enemy != null and is_instance_valid(_chain_enemy):
		n += 1
	return n

# --- Helpers ---

func _active_in_radius(center: Vector3, radius: float) -> bool:
	var pos := _get_character_position(_get_active_character())
	return Vector2(pos.x - center.x, pos.z - center.z).length() <= radius

func _all_party_in_radius(center: Vector3, radius: float) -> bool:
	var gs = _get_game_state()
	var any := false
	for char_id in PARTY_IDS:
		if gs != null and not gs.characters.has(char_id):
			continue
		any = true
		var pos := _get_character_position(char_id)
		if Vector2(pos.x - center.x, pos.z - center.z).length() > radius:
			return false
	return any

func _add_marker(pos: Vector3, size: Vector3, color: Color, energy: float, label: String) -> StandardMaterial3D:
	var mat := _make_material(color * 0.4, color, energy)
	var mesh := _add_box(self, pos - Vector3(0, 0.2, 0), size, color * 0.4)
	mesh.material_override = mat
	_add_label(self, label, pos + Vector3(0, 1.7, 0), color)
	return mat

func _add_flora(pos: Vector3, bloom_mat: StandardMaterial3D, flora_scale: float) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var stem_mat := _make_material(Color(0.12, 0.16, 0.12))
	for i in range(3):
		var angle := float(i) * TAU / 3.0
		var stem := _add_box(root, Vector3(cos(angle) * 0.12, 0.28 * flora_scale, sin(angle) * 0.12),
			Vector3(0.05, 0.56 * flora_scale, 0.05), Color(0.12, 0.16, 0.12))
		stem.material_override = stem_mat
		var bloom := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.13 * flora_scale
		sphere.height = 0.26 * flora_scale
		bloom.mesh = sphere
		bloom.material_override = bloom_mat
		bloom.position = Vector3(cos(angle) * 0.12, 0.56 * flora_scale, sin(angle) * 0.12)
		root.add_child(bloom)

func _update_visual_state() -> void:
	if _patch_material != null:
		_patch_material.emission_energy_multiplier = 0.9 if _patch_concealed else 0.5
	if _slit_material != null:
		var slit_lit := _slit_window_until > 0.0 or _slit_phase == "safe"
		_slit_material.emission_energy_multiplier = 0.8 if slit_lit else 0.35
	if _spot_material != null:
		var spot_lit := _spot_sweep_until > 0.0 or _spot_phase == "safe"
		_spot_material.emission_energy_multiplier = 0.8 if spot_lit else 0.35
