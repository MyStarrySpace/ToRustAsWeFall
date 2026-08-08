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
const FlureScript := preload("res://scripts/game/objects/flure.gd")
const FixedCadenceScript := preload("res://scripts/system/core/fixed_cadence.gd")
const HazardFieldScript := preload("res://scripts/game/objects/hazard_field.gd")
const HushbloomScript := preload("res://scripts/game/objects/hushbloom.gd")
const ScarpetScript := preload("res://scripts/game/objects/scarpet.gd")

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
const SLIT_FLURE_POS := Vector3(45.0, 0.45, 6.5)
const SLIT_FLURE_SETTLE_POS := Vector3(42.0, 0.5, 9.0)
const SPOT_SWEEP_CONTROL_POS := Vector3(58.0, 0.45, -1.4)

const SHELTER_RADIUS := 2.8
const SHELTER_SIZE := Vector2(SHELTER_RADIUS * 2.0, SHELTER_RADIUS * 2.0)
const PATCH_RADIUS := 2.5
const STATION_RADIUS := 2.4
const SPOT_RADIUS := 3.4
const ROUTE_COMMIT_MIN_X := 18.0
const ROUTE_COMMIT_MAX_X := 39.0
const ROUTE_COMMIT_RADIUS := 2.8
const SLIT_WINDOW := 6.0
const SPOT_SWEEP := 6.0
const SPOT_PROBE_INTERVAL := 0.25
const SPATIAL_AUTHORITY_INTERVAL := 0.1
const RISKY_BLOOM_DAMAGE_PER_TICK := 5.5
const RISKY_BLOOM_TICK_INTERVAL := 1.0
const REFUGE_AUTHORITY_VERSION := 4
const VALID_ROUTE_PHASES := ["briefing", "underway", "failed", "complete"]
const VALID_SLIT_PHASES := ["ready", "window", "safe", "failed"]
const VALID_SPOT_PHASES := ["ready", "sweeping", "safe", "failed"]
const VALID_EXIT_REST_PHASES := ["locked", "ready", "committing", "rested"]

const SPAWNS := {
	# Character roots are feet transforms. The entry shelter pad is centred at
	# ENTRY_SHELTER_POS.y + 0.03 with 0.08 m thickness, so its top is Y=0.52.
	"aster": Vector3(7.4, 0.52, 1.4),
	"peris": Vector3(5.6, 0.52, 0.0),
	"endo": Vector3(6.2, 0.52, -1.6),
}

var _route_phase := "briefing"
var _route_choice := ""
var _route_commit_actor := ""
var _route_commit_position: Array = []
var _last_outcome := ""
var _hazard_taken := false
var _patch_concealed := false
var _slit_phase := "ready"
var _slit_window_until := -1.0
var _spot_phase := "ready"
var _spot_sweep_until := -1.0
var _spot_probe_tick := -1.0
var _shelter_reached := false
var _exit_rest_phase := "locked"
var _exit_rest_commit_tick := -1.0
var _exit_rest_commit_day := 0
var _exit_rest_before_atp: Dictionary = {}
var _spatial_authority_epoch := -1.0
var _next_spatial_authority_tick := -1.0

var _standard_enemy
var _chain_enemy
var _slit_flure
var _entry_hushbloom
var _north_scarpet
var _risky_bloom_field
var _spot_sweep_interactable
var _patch_material: StandardMaterial3D
var _slit_material: StandardMaterial3D
var _spot_material: StandardMaterial3D
var _hushbloom_material: StandardMaterial3D
var _risky_bloom_material: StandardMaterial3D
var _exit_shelter_interactable
var _refuge_authority_initialized := false
var _restoring_refuge_authority := false
var _refuge_authority_baseline: Dictionary = {}

func _build_chunk() -> void:
	_add_floor(self, FLOOR_CENTER, FLOOR_SIZE, Color(0.085, 0.09, 0.11))
	_add_box(self, Vector3(35.0, 2.4, -14.1), Vector3(76.0, 4.8, 0.3), Color(0.13, 0.14, 0.16))
	_add_box(self, Vector3(35.0, 2.4, 14.1), Vector3(76.0, 4.8, 0.3), Color(0.13, 0.14, 0.16))
	for i in range(8):
		var blend := float(i) / 7.0
		_add_light(self, Vector3(6.0 + float(i) * 9.0, 3.4, 0.0),
			Color(0.26 + blend * 0.2, 0.3 + blend * 0.14, 0.4 - blend * 0.1), 1.1 + blend * 1.1, 13.0)

	_build_refuge_shelter(ENTRY_SHELTER_POS, "ENTRY SHELTER", Color(0.2, 0.5, 0.7), false)
	_build_refuge_shelter(EXIT_SHELTER_POS, "EXIT SHELTER", Color(0.3, 0.7, 0.45), true)
	_add_label(self, "FORK", FORK_POS + Vector3(0, 2.2, 0))
	_build_route_commit_markers()

	# North (safe) lane + a real Scarpet. The pad's spatial conceals() predicate feeds
	# GameState concealment, which is the same truth the sentries read.
	_add_box(self, Vector3(28.0, -0.04, NORTH_LANE_Z), Vector3(26.0, 0.06, 5.0), Color(0.1, 0.12, 0.1))
	_patch_material = _make_material(Color(0.16, 0.3, 0.16), Color(0.3, 0.85, 0.4), 0.5)
	var patch := _add_box(self, CONCEAL_PATCH_POS - Vector3(0, 0.42, 0), Vector3(PATCH_RADIUS * 2.0, 0.08, PATCH_RADIUS * 2.0), Color(0.16, 0.3, 0.16))
	patch.material_override = _patch_material
	_north_scarpet = ScarpetScript.new()
	_north_scarpet.name = "NorthScarpet"
	_north_scarpet.configure(CONCEAL_PATCH_POS, PATCH_RADIUS, false)
	add_child(_north_scarpet)
	_add_label(self, "SCARPET — MEDIUM COVER", CONCEAL_PATCH_POS + Vector3(0, 1.8, 0), Color(0.5, 0.9, 0.6))

	# South (direct) lane + hazard bloom.
	_add_box(self, Vector3(28.0, -0.04, SOUTH_LANE_Z), Vector3(26.0, 0.06, 5.0), Color(0.12, 0.1, 0.1))
	_risky_bloom_material = _make_material(Color(0.32, 0.14, 0.1), Color(0.95, 0.32, 0.12), 0.6)
	_add_flora(RISKY_BLOOM_POS, _risky_bloom_material, 0.7)
	_add_label(self, "RUST BLOOM", RISKY_BLOOM_POS + Vector3(0, 1.8, 0), Color(0.95, 0.5, 0.35))

	# The entry plant is the reusable Hushbloom object: any body can trip its real
	# scheduler-owned stun burst. It is not a decorative "tend" checkbox.
	_hushbloom_material = _make_material(Color(0.2, 0.26, 0.34), Color(0.45, 0.6, 0.95), 0.15)
	_add_box(self, HUSHBLOOM_POS - Vector3(0, 0.42, 0), Vector3(1.1, 0.06, 1.1), Color(0.1, 0.13, 0.18))
	_add_label(self, "HUSHBLOOM — BODY TRIGGER", HUSHBLOOM_POS + Vector3(0, 1.6, 0), Color(0.6, 0.75, 1.0))

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
	_build_system_objects()
	_build_spot_sweep_control()
	_initialize_refuge_authority()
	_update_concealment()
	_update_visual_state()
	_apply_refuge_interaction_presenters()
	_set_preview_step("refuge_run_briefing")

func _process(delta: float) -> void:
	_update_presentation(delta)

func headless_process(delta: float) -> void:
	_update_presentation(delta)

# --- Scene metadata ---

func get_scene_title() -> String:
	return "Refuge Run"

func get_scene_help() -> String:
	return "Cross a marked fork lane to commit it, use Scarpet cover or risk the spatial rust-bloom field, light the slit Flure to pull the real sentries away, then gather at the shelter spot and click its sweep control before reaching the exit."

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
		"slit_flure": SLIT_FLURE_POS,
		"standard_sentry": STANDARD_ENEMY_POS,
		"chain_seam": CHAIN_ENEMY_POS,
		"converge": CONVERGE_POS,
		"hide_slit": HIDE_SLIT_POS,
		"hide_spot": HIDE_SPOT_POS,
		"spot_sweep_control": SPOT_SWEEP_CONTROL_POS,
		"exit_shelter": EXIT_SHELTER_POS,
	}, true)
	return anchors

func get_preview_time_state() -> Dictionary:
	return {
		"day": 4,
		"time": 0.82,
		"routing_mode": "safe",
		"note_default": "The bloom burns only bodies inside it; Scarpet/slit/spot cover writes the same concealment truth both live sentries read. The Flure physically redirects those sentries before the shelter sweep.",
	}

func get_preview_abilities() -> Array:
	# Display names + descriptions + tuning live in data/abilities/en/abilities.xlsx (per-context rows).
	return AbilityData.for_context("refuge_run")
func get_preview_state() -> Dictionary:
	return {
		"route_phase": _route_phase,
		"route_choice": _route_choice,
		"route_commit_actor": _route_commit_actor,
		"route_commit_position": _route_commit_position.duplicate(),
		"last_outcome": _last_outcome,
		"hazard_taken": _hazard_taken,
		"patch_concealed": _patch_concealed,
		"slit_phase": _slit_phase,
		"slit_window_open": _slit_window_until > 0.0,
		"slit_window_remaining": maxf(0.0, _slit_window_until - _get_scheduler_tick()) if _slit_window_until >= 0.0 else 0.0,
		"slit_occupied": _any_party_in_radius(HIDE_SLIT_POS, STATION_RADIUS),
		"spot_phase": _spot_phase,
		"spot_sweep_active": _spot_sweep_until > 0.0,
		"spot_sweep_remaining": maxf(0.0, _spot_sweep_until - _get_scheduler_tick()) if _spot_sweep_until >= 0.0 else 0.0,
		"spot_control_enabled": _spot_sweep_interactable != null \
			and _spot_sweep_interactable.is_interaction_enabled(),
		"shelter_reached": _shelter_reached,
		"exit_rest_phase": _exit_rest_phase,
		"hiding_type_count": 3,
		"enemy_count": _enemy_count(),
		"plant_count": 2,
		"route_count": 2,
		"enemy": {
			"standard": _enemy_report(_standard_enemy),
			"chain": _enemy_report(_chain_enemy),
		},
		"slit_flure": _slit_flure.get_effect_state() if _slit_flure != null else {},
		"hushbloom": _entry_hushbloom.get_authority_state() if _entry_hushbloom != null else {},
		"hazard": _risky_bloom_field.get_state() if _risky_bloom_field != null else {},
	}

func get_preview_overlay_status(overlay_id: String, _current_tick: float) -> Array:
	match overlay_id:
		"aster":
			return ["DATA: fork splits safe-north / direct-south.", "Route: %s" % (_route_choice if _route_choice != "" else "unset")]
		"peris":
			return ["FOG: Scarpet is partial cover; the rust bloom is a live spatial field.", "Hushbloom fires when any body crosses its trigger."]
		"endo":
			return ["Seam: the Flure moves the sentries; the slit supplies full cover while it sings.", "The spot holds only while nobody is actually acquired."]
	return []


## Stable semantic targets let deterministic QA enter through the same interaction coordinator
## as a right-click. Route selection deliberately has no target: walking through a lane owns it.
func get_playthrough_interaction_target(action_id: String) -> Node3D:
	match action_id:
		"slit_flure":
			return _slit_flure as Node3D
		"spot_sweep":
			return _spot_sweep_interactable as Node3D
		"exit_shelter":
			return _exit_shelter_interactable as Node3D
	return null


# --- Public chunk methods (driven by scenarios / play) ---

func reset_preview_state() -> void:
	_cancel_refuge_callbacks()
	_route_phase = "briefing"
	_route_choice = ""
	_route_commit_actor = ""
	_route_commit_position.clear()
	_last_outcome = ""
	_hazard_taken = false
	_patch_concealed = false
	_slit_phase = "ready"
	_slit_window_until = -1.0
	_spot_phase = "ready"
	_spot_sweep_until = -1.0
	_spot_probe_tick = -1.0
	_shelter_reached = false
	_exit_rest_phase = "locked"
	_clear_exit_rest_context()
	_spatial_authority_epoch = -1.0
	_next_spatial_authority_tick = -1.0
	if _slit_flure != null:
		_slit_flure.reset_flure()
	if is_instance_valid(_spot_sweep_interactable):
		_spot_sweep_interactable.reset()
	if is_instance_valid(_exit_shelter_interactable):
		_exit_shelter_interactable.reset()
	if _risky_bloom_field != null:
		_risky_bloom_field.set_active(true)
	_update_concealment()
	_update_visual_state()
	_apply_refuge_interaction_presenters()
	_set_preview_step("refuge_run_briefing")
	_restart_spatial_authority()
	_publish_refuge_authority()

## Deliberately inert. Route truth comes only from a conscious body sampled inside an
## authored threshold on the saved spatial cadence; a remote method call cannot manufacture it.
func choose_route(_route_id: String) -> bool:
	return false


func _commit_route_from_body(route_id: String, actor_id: String, at_position: Vector3) -> bool:
	if _route_phase in ["failed", "complete"]:
		return false
	if _route_choice != "":
		_last_outcome = "route_already_committed:%s" % _route_choice
		_publish_refuge_authority()
		return false
	if route_id != "north" and route_id != "south":
		_last_outcome = "bad_route:%s" % route_id
		_publish_refuge_authority()
		return false
	var gs = _get_game_state()
	if gs == null or actor_id not in PARTY_IDS or not gs.characters.has(actor_id) \
			or gs.is_downed(actor_id) or not at_position.is_finite() \
			or _route_for_position(at_position) != route_id \
			or not gs.get_position(actor_id).is_equal_approx(at_position):
		return false
	_route_choice = route_id
	_route_phase = "underway"
	_route_commit_actor = actor_id
	_route_commit_position = _vector3_record(at_position)
	if route_id == "south":
		_last_outcome = "route:south"
		_show_message(
			"%s crosses the south threshold. It is shorter, but the visible rust bloom burns only whoever enters it."
				% _actor_label(actor_id),
			2.2)
	else:
		_last_outcome = "route:%s" % route_id
		_show_message(
			"%s crosses the north threshold. This lane bends through Scarpet cover."
				% _actor_label(actor_id),
			1.9)
	_set_preview_step("refuge_run_%s" % route_id)
	_apply_refuge_interaction_presenters()
	_publish_refuge_authority()
	return true


## The fork is a spatial commitment, not a prompt. The fixed gameplay cadence records whichever
## conscious party body first crosses one of the two painted lane bands.
func _evaluate_route_body_receipts() -> void:
	if _route_phase != "briefing" or _route_choice != "":
		return
	var gs = _get_game_state()
	if gs == null:
		return
	for char_id in PARTY_IDS:
		if not gs.characters.has(char_id) or gs.is_downed(char_id):
			continue
		var position := _get_character_position(char_id)
		var route_id := _route_for_position(position)
		if route_id != "":
			_commit_route_from_body(route_id, char_id, position)
			return

## Deliberately inert. Hushbloom has no fictional tend
## verb: its reusable object fires when any body crosses the trigger.
func tend_bloom() -> bool:
	return false

## Deliberately inert. A player must trigger the registered Flure with a real body.
func activate_slit_lure() -> bool:
	return false


func _on_slit_flure_activated(pulled: int, source: Node) -> void:
	if pulled <= 0 or _route_phase != "underway" or _slit_phase != "ready" \
			or source != _slit_flure or not _slit_flure_receipt_pending(source):
		_apply_refuge_interaction_presenters()
		return
	var effect: Dictionary = _slit_flure.get_effect_state()
	var deadline := float(effect.get("end_tick", -1.0))
	if str(effect.get("phase", "")) != FlureScript.PHASE_ACTIVE \
			or deadline < _get_scheduler_tick():
		_last_outcome = "slit_flure_missing_active_effect"
		_apply_refuge_interaction_presenters()
		_publish_refuge_authority()
		return
	_slit_window_until = deadline
	_slit_phase = "window"
	_last_outcome = "slit_window_open"
	_set_preview_step("refuge_run_slit")
	_show_message(
		"The Flure physically pulls %d sentr%s south. Reach the slit before its song ends."
			% [pulled, "y" if pulled == 1 else "ies"],
		1.9)
	_arm_slit_resolution(_slit_window_until)
	_apply_refuge_interaction_presenters()
	_publish_refuge_authority()

## The visible pulse control supplies its exact accepted one-shot receipt. Direct calls are inert.
func activate_spot_sweep(source: Node = null) -> bool:
	if not _spot_sweep_receipt_pending(source):
		return false
	if _route_phase in ["failed", "complete"]:
		return false
	if _slit_phase != "safe" or _spot_phase in ["sweeping", "safe", "failed"]:
		return false
	_spot_sweep_until = _get_scheduler_tick() + SPOT_SWEEP
	_spot_phase = "sweeping"
	_update_concealment()
	_last_outcome = "spot_sweep_active"
	_set_preview_step("refuge_run_spot")
	_show_message("The real sentries sweep the spot. Cover holds unless one actually acquires a target.", 1.8)
	_spot_probe_tick = minf(_spot_sweep_until, _get_scheduler_tick() + SPOT_PROBE_INTERVAL)
	_arm_spot_probe(_spot_probe_tick)
	_apply_refuge_interaction_presenters()
	_publish_refuge_authority()
	return true

## Reach the exit shelter through its exact accepted one-shot receipt. Direct calls are inert.
func reach_exit(source: Node = null) -> bool:
	if not _exit_shelter_receipt_pending(source):
		return false
	if _route_phase in ["failed", "complete"]:
		return false
	if _slit_phase != "safe" or _spot_phase != "safe":
		_last_outcome = "exit_refuges_incomplete"
		return false
	if _exit_rest_phase != "ready":
		return false
	var preflight := _preflight_authored_party_rest(
		EXIT_SHELTER_POS, SHELTER_SIZE, PARTY_IDS)
	var blocked := preflight.get("blocked", []) as Array
	if not blocked.is_empty():
		_rearm_refuge_control(source)
		return false
	var gs = _get_game_state()
	if gs == null:
		return false
	_exit_rest_phase = "committing"
	_exit_rest_commit_tick = _get_scheduler_tick()
	_exit_rest_commit_day = gs.get_game_day()
	_exit_rest_before_atp = (preflight.get("before_atp", {}) as Dictionary).duplicate(true)
	_apply_refuge_interaction_presenters()
	_publish_refuge_authority()
	if not bool(gs.command_party_rest(PARTY_IDS)):
		_exit_rest_phase = "ready"
		_clear_exit_rest_context()
		_rearm_refuge_control(source)
		_apply_refuge_interaction_presenters()
		_publish_refuge_authority()
		return false
	_complete_exit_shelter_rest(true)
	return true


func _complete_exit_shelter_rest(show_feedback := false) -> void:
	if _exit_rest_phase == "rested":
		return
	_cancel_exit_rest_callback()
	_exit_rest_phase = "rested"
	_shelter_reached = true
	_route_phase = "complete"
	_last_outcome = "success"
	_clear_exit_rest_context()
	_set_preview_step("refuge_run_complete")
	if show_feedback:
		_show_note(
			"The full conscious party rests inside the exit shelter. The stretch is crossed.",
			2.5)
	_apply_refuge_interaction_presenters()
	_publish_refuge_authority()


func _clear_exit_rest_context() -> void:
	_exit_rest_commit_tick = -1.0
	_exit_rest_commit_day = 0
	_exit_rest_before_atp.clear()


func _exit_rest_tag() -> String:
	return "refuge_run_exit_rest:%s" % refuge_authority_key().sha256_text().substr(0, 12)


func _cancel_exit_rest_callback() -> void:
	var scheduler = _get_scheduler()
	if scheduler != null:
		scheduler.cancel_tag(_exit_rest_tag())


func _arm_exit_rest_callback() -> void:
	var scheduler = _get_scheduler()
	if scheduler == null or _exit_rest_phase != "committing":
		return
	scheduler.cancel_tag(_exit_rest_tag())
	scheduler.schedule_at(
		maxf(_get_scheduler_tick(), _exit_rest_commit_tick),
		_resume_committed_exit_rest.bind(_exit_rest_commit_tick),
		_exit_rest_tag())


func _resume_committed_exit_rest(expected_tick: float) -> void:
	if _exit_rest_phase != "committing" \
			or not is_equal_approx(_exit_rest_commit_tick, expected_tick):
		return
	if _authored_party_rest_effect_matches(
			PARTY_IDS, _exit_rest_before_atp, _exit_rest_commit_day):
		_complete_exit_shelter_rest(true)
		return
	var preflight := _preflight_authored_party_rest(
		EXIT_SHELTER_POS, SHELTER_SIZE, PARTY_IDS)
	if not (preflight.get("blocked", []) as Array).is_empty():
		_exit_rest_phase = "ready"
		_clear_exit_rest_context()
		_apply_refuge_interaction_presenters()
		_publish_refuge_authority()
		return
	var gs = _get_game_state()
	if gs != null and bool(gs.command_party_rest(PARTY_IDS)):
		_complete_exit_shelter_rest(true)


# --- Derived spatial state + scheduler-owned resolutions ---

## Render/headless work is a projection only. Route commitment and concealment are sampled by the
## saved fixed cadence below, so extra frames or a manually invoked presenter cannot change truth.
func _update_presentation(_delta: float) -> void:
	_refresh_patch_concealed_projection()
	_update_visual_state()


func _restart_spatial_authority() -> void:
	var scheduler = _get_scheduler()
	if scheduler == null:
		_spatial_authority_epoch = -1.0
		_next_spatial_authority_tick = -1.0
		return
	scheduler.cancel_tag(_spatial_authority_tag())
	var now := _get_scheduler_tick()
	_spatial_authority_epoch = now
	_next_spatial_authority_tick = FixedCadenceScript.next_strict_tick(
		_spatial_authority_epoch, SPATIAL_AUTHORITY_INTERVAL, now)
	_arm_spatial_authority(_next_spatial_authority_tick)


func _arm_spatial_authority(deadline: float) -> void:
	var scheduler = _get_scheduler()
	if scheduler == null or deadline < 0.0:
		return
	scheduler.cancel_tag(_spatial_authority_tag())
	scheduler.schedule_at(
		maxf(_get_scheduler_tick(), deadline),
		_spatial_authority_tick.bind(deadline),
		_spatial_authority_tag())


func _spatial_authority_tick(expected_tick: float) -> void:
	if not is_equal_approx(_next_spatial_authority_tick, expected_tick):
		return
	var now := _get_scheduler_tick()
	_next_spatial_authority_tick = FixedCadenceScript.next_strict_tick(
		_spatial_authority_epoch, SPATIAL_AUTHORITY_INTERVAL, now)
	# Publish the future cadence edge before any route/concealment signal can expose a save seam.
	# A capture from inside one of those effects therefore reconstructs one future poll, never the
	# callback currently being consumed.
	_publish_refuge_authority()
	_evaluate_route_body_receipts()
	_update_concealment()
	_arm_spatial_authority(_next_spatial_authority_tick)
	_publish_refuge_authority()


func _spatial_authority_tag() -> String:
	return "refuge_run_spatial:%s" % refuge_authority_key().sha256_text().substr(0, 12)

func _fail(reason: String) -> void:
	_cancel_refuge_callbacks()
	_route_phase = "failed"
	_last_outcome = reason
	if _slit_phase == "window":
		_slit_phase = "failed"
	if _spot_phase == "sweeping":
		_spot_phase = "failed"
	_restart_spatial_authority()
	_set_preview_step("refuge_run_failed")
	_apply_refuge_interaction_presenters()
	_publish_refuge_authority()

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
	if not _standard_enemy.hit_target.is_connected(_on_enemy_hit_target):
		_standard_enemy.hit_target.connect(_on_enemy_hit_target)
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
	if not _chain_enemy.hit_target.is_connected(_on_enemy_hit_target):
		_chain_enemy.hit_target.connect(_on_enemy_hit_target)
	if _chain_enemy.has_method("set_wall_line"):
		_chain_enemy.set_wall_line(Vector3(31.0, 0.5, 12.0), Vector3(0, 0, -1))
	if _chain_enemy.has_method("set_patrol"):
		var chain_patrol: Array[Vector3] = [Vector3(28.0, 0.0, SOUTH_LANE_Z), Vector3(34.0, 0.0, SOUTH_LANE_Z)]
		_chain_enemy.set_patrol(chain_patrol)


func _build_system_objects() -> void:
	var gs = _get_game_state()
	var scheduler = _get_scheduler()
	if gs == null or scheduler == null:
		return

	_risky_bloom_field = HazardFieldScript.new()
	_risky_bloom_field.name = "SouthRustBloomField"
	add_child(_risky_bloom_field)
	_risky_bloom_field.setup(
		gs,
		scheduler,
		Vector2(20.0, SOUTH_LANE_Z - 2.35),
		Vector2(38.0, SOUTH_LANE_Z + 2.35),
		PARTY_IDS,
		{
			"dps_tick": RISKY_BLOOM_DAMAGE_PER_TICK,
			"interval": RISKY_BLOOM_TICK_INTERVAL,
			"tag": "refuge_run_south_bloom",
			"on_bite": Callable(self, "_on_rust_bloom_bite"),
		}
	)
	_risky_bloom_field.set_active(true)

	_entry_hushbloom = HushbloomScript.new()
	_entry_hushbloom.name = "RefugeEntryHushbloom"
	_entry_hushbloom.authority_id = "refuge_run_entry_hushbloom"
	_entry_hushbloom.configure(gs, HUSHBLOOM_POS, {
		"trigger_radius": 1.5,
		"stun_radius": 4.2,
		"stun_secs": 6.0,
		"regen_secs": 45.0,
		"pickable": false,
	})
	_entry_hushbloom.set_enemy_provider(Callable(self, "_refuge_enemies"))
	add_child(_entry_hushbloom)

	_slit_flure = FlureScript.new()
	_slit_flure.name = "SlitFlure"
	_slit_flure.authority_id = "refuge_run_slit_flure"
	_slit_flure.configure(
		gs,
		SLIT_FLURE_POS,
		["refuge_standard", "refuge_chain"],
		90.0,
		1.6,
		Color(0.96, 0.72, 0.24)
	)
	_slit_flure.settle_pos = SLIT_FLURE_SETTLE_POS
	_slit_flure.lure_duration = SLIT_WINDOW
	_slit_flure.set_enemy_resolver(Callable(self, "_resolve_refuge_enemy"))
	_slit_flure.set_pre_trigger_validator(_validate_slit_flure_trigger)
	add_child(_slit_flure)
	_register_interactable(_slit_flure)
	_slit_flure.consequence_preview = \
		"Redirect the two live sentries toward the south settle point for six seconds"
	if not _slit_flure.flure_activated.is_connected(_on_slit_flure_activated):
		_slit_flure.flure_activated.connect(_on_slit_flure_activated.bind(_slit_flure))
	_add_label(self, "FLURE — MOVES SENTRIES", SLIT_FLURE_POS + Vector3(0.0, 1.6, 0.0), Color(1.0, 0.8, 0.35))


func _build_route_commit_markers() -> void:
	for route_id in ["north", "south"]:
		var lane_z := NORTH_LANE_Z if route_id == "north" else SOUTH_LANE_Z
		var tint := Color(0.35, 0.78, 0.48) if route_id == "north" \
			else Color(0.92, 0.42, 0.2)
		var marker_pos := Vector3(ROUTE_COMMIT_MIN_X + 1.0, 0.02, lane_z)
		var marker := _add_box(
			self,
			marker_pos,
			Vector3(2.0, 0.05, ROUTE_COMMIT_RADIUS * 2.0),
			tint.darkened(0.68))
		marker.material_override = _make_material(tint.darkened(0.68), tint, 0.45)
		_add_label(
			self,
			"%s THRESHOLD // CROSS TO COMMIT" % route_id.to_upper(),
			marker_pos + Vector3(0.0, 1.1, 0.0),
			tint)


func _build_spot_sweep_control() -> void:
	var housing := _add_box(
		self,
		SPOT_SWEEP_CONTROL_POS + Vector3(0.0, 0.65, 0.0),
		Vector3(0.85, 1.3, 0.85),
		Color(0.09, 0.12, 0.1))
	var pulse_mat := _make_material(
		Color(0.18, 0.28, 0.16), Color(0.72, 1.0, 0.42), 0.65)
	var pulse := _add_box(
		self,
		SPOT_SWEEP_CONTROL_POS + Vector3(0.0, 1.25, 0.0),
		Vector3(0.58, 0.18, 0.58),
		Color(0.18, 0.28, 0.16))
	pulse.material_override = pulse_mat
	_spot_sweep_interactable = _add_object_interactable(
		self,
		"SpotSweepControl",
		"Draw the sentry sweep across this shelter spot",
		SPOT_SWEEP_CONTROL_POS,
		"DRAW SWEEP",
		[housing, pulse],
		"",
		0.0,
		true,
		1.5,
		Interactable.InteractableType.INSPECTION)
	_spot_sweep_interactable.consequence_preview = \
		"Start a six-second sentry sweep; exposed party members can be acquired"
	_spot_sweep_interactable.set_pre_trigger_validator(_validate_spot_sweep_trigger)
	_spot_sweep_interactable.interacted.connect(
		activate_spot_sweep.bind(_spot_sweep_interactable))
	_add_label(
		self,
		"SWEEP PULSE // GATHER, THEN DRAW WATCH",
		SPOT_SWEEP_CONTROL_POS + Vector3(0.0, 2.05, 0.0),
		Color(0.72, 1.0, 0.42))


## These guards run before Interactable records a one-shot. They prove exact source, exact body,
## canonical proximity, and the current causal prerequisites before any positive transition.
func _validate_slit_flure_trigger(source: Node, actor: String) -> bool:
	if source == null or source != _slit_flure \
			or _route_phase != "underway" or _slit_phase != "ready":
		return false
	var effect: Dictionary = _slit_flure.get_effect_state()
	return str(effect.get("phase", "")) == FlureScript.PHASE_READY \
		and _refuge_enemy_available_for_lure() \
		and _interaction_actor_ready_at(source, actor)


func _validate_spot_sweep_trigger(source: Node, actor: String) -> bool:
	return source != null and source == _spot_sweep_interactable \
		and _route_phase == "underway" and _slit_phase == "safe" \
		and _spot_phase == "ready" \
		and _interaction_actor_ready_at(source, actor) \
		and _all_party_in_radius(HIDE_SPOT_POS, SPOT_RADIUS)


func _validate_exit_shelter_trigger(source: Node, actor: String) -> bool:
	if source == null or source != _exit_shelter_interactable \
			or _route_phase != "underway" or _slit_phase != "safe" \
			or _spot_phase != "safe" or _exit_rest_phase != "ready" \
			or not _interaction_actor_ready_at(source, actor):
		return false
	# Fragment previews project their own non-linear day/night clock. Commit that
	# displayed time only at this exact physical command boundary, before canonical
	# GameState decides whether the trio may rest. Otherwise the HUD can show night
	# while the shelter silently validates against the preview's stale daytime clock.
	_sync_host_clock_to_game_state()
	return (_preflight_authored_party_rest(
		EXIT_SHELTER_POS, SHELTER_SIZE, PARTY_IDS).get("blocked", []) as Array).is_empty()


func _slit_flure_receipt_pending(source: Node) -> bool:
	if source == null or source != _slit_flure \
			or _route_phase != "underway" or _slit_phase != "ready" \
			or not _one_shot_receipt_pending(source):
		return false
	var actor := str(source.get("active_character"))
	var effect: Dictionary = _slit_flure.get_effect_state()
	var report: Dictionary = effect.get("last_activation_report", {}) as Dictionary
	return _interaction_actor_ready_at(source, actor) \
		and str(effect.get("phase", "")) == FlureScript.PHASE_ACTIVE \
		and int(report.get("pulled", 0)) > 0


func _spot_sweep_receipt_pending(source: Node) -> bool:
	if source == null or source != _spot_sweep_interactable \
			or not _one_shot_receipt_pending(source):
		return false
	var actor := str(source.get("active_character"))
	return _validate_spot_sweep_trigger(source, actor)


func _exit_shelter_receipt_pending(source: Node) -> bool:
	if source == null or source != _exit_shelter_interactable \
			or not _one_shot_receipt_pending(source):
		return false
	var actor := str(source.get("active_character"))
	return _validate_exit_shelter_trigger(source, actor)


func _one_shot_receipt_pending(source: Node) -> bool:
	if source == null or not bool(source.get("one_shot")) \
			or not bool(source.get("_used")) \
			or bool(source.get("interaction_enabled")):
		return false
	var gs = _get_game_state()
	var data_id := str(source.get("data_id"))
	if gs != null and data_id != "" and gs.has_interactable(data_id):
		var spec: Dictionary = gs.get_interactable(data_id)
		return bool(spec.get("one_shot", false)) \
			and bool(spec.get("triggered", false)) \
			and not gs.is_interactable_enabled(data_id)
	return true


func _interaction_actor_ready_at(source: Node, actor: String) -> bool:
	var gs = _get_game_state()
	if gs == null or source == null or not (source is Node3D) \
			or actor not in PARTY_IDS or not gs.characters.has(actor) \
			or not gs.is_narratively_available(actor) \
			or gs.is_downed(actor) or gs.is_knocked_down(actor) \
			or gs.is_moving(actor) or gs.is_resting(actor) or gs.is_dodging(actor) \
			or gs.is_endocytosing(actor) or gs.is_external_traversal_active(actor) \
			or gs.is_dragging(actor) or gs.is_field_restoring(actor):
		return false
	var radius := float(source.get("interaction_radius")) + 0.15
	return _position_in_radius(
		gs.get_position(actor), _interaction_data_position(source as Node3D), radius)


func _interaction_data_position(source: Node3D) -> Vector3:
	var gs = _get_game_state()
	var data_id := str(source.get("data_id"))
	if gs != null and data_id != "" and gs.has_interactable(data_id):
		var position: Variant = gs.get_interactable(data_id).get("position", Vector3.ZERO)
		if position is Vector3:
			return position
	var position := source.global_position
	if gs != null and gs.coord_map != null and gs.coord_map.has_method("to_data"):
		position = gs.coord_map.to_data(position)
	return position


func _refuge_enemy_available_for_lure() -> bool:
	for enemy in _refuge_enemies():
		if enemy.has_method("get_lure_availability") \
				and str(enemy.get_lure_availability()) == "available":
			return true
	return false


func _rearm_refuge_control(source: Node) -> void:
	if source != null and source.has_method("reset"):
		source.call("reset")
	_apply_refuge_interaction_presenters()


func _refuge_enemies() -> Array:
	var enemies: Array = []
	for enemy in [_standard_enemy, _chain_enemy]:
		if enemy != null and is_instance_valid(enemy):
			enemies.append(enemy)
	return enemies


func _resolve_refuge_enemy(enemy_id: String):
	match enemy_id:
		"refuge_standard": return _standard_enemy
		"refuge_chain": return _chain_enemy
	return null


func _on_rust_bloom_bite(char_id: String) -> void:
	_hazard_taken = true
	_last_outcome = "rust_bloom_bit:%s" % char_id
	_show_message("%s is inside the rust bloom field." % char_id.capitalize(), 1.2)
	_publish_refuge_authority()


func _on_enemy_hit_target(target_id: String, _damage: float) -> void:
	var gs = _get_game_state()
	_last_outcome = "sentry_hit:%s" % target_id
	if gs != null and gs.has_method("is_downed") and gs.is_downed(target_id):
		_fail("party_member_downed:%s" % target_id)
	else:
		_publish_refuge_authority()

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


# --- Spatial concealment and timed refuge resolution ---

func _update_concealment() -> void:
	var gs = _get_game_state()
	if gs == null or not gs.has_method("set_character_concealment"):
		return
	# Cover remains in force through the inclusive resolution instant. The deadline
	# callback evaluates the sweep first, then clears the derived concealment.
	var slit_open := _slit_phase == "window" and _slit_window_until + 0.000001 >= _get_scheduler_tick()
	var spot_open := _spot_phase == "sweeping" and _spot_sweep_until + 0.000001 >= _get_scheduler_tick()
	for char_id in PARTY_IDS:
		if not gs.characters.has(char_id):
			continue
		var position := _get_character_position(char_id)
		var tier := GameState.CONCEAL_NONE
		if _north_scarpet != null and _north_scarpet.conceals(position):
			tier = GameState.CONCEAL_MEDIUM
		if slit_open and _position_in_radius(position, HIDE_SLIT_POS, STATION_RADIUS):
			tier = GameState.CONCEAL_FULL
		if spot_open and _position_in_radius(position, HIDE_SPOT_POS, SPOT_RADIUS):
			tier = GameState.CONCEAL_FULL
		gs.set_character_concealment(char_id, tier)
	_refresh_patch_concealed_projection()


func _refresh_patch_concealed_projection() -> void:
	var gs = _get_game_state()
	if gs == null:
		_patch_concealed = false
		return
	var active_id := _get_active_character()
	_patch_concealed = active_id != "" and gs.characters.has(active_id) \
		and _north_scarpet != null and _north_scarpet.conceals(_get_character_position(active_id)) \
		and gs.get_character_concealment(active_id) >= GameState.CONCEAL_MEDIUM


func _arm_slit_resolution(deadline: float) -> void:
	var scheduler = _get_scheduler()
	if scheduler == null or _slit_phase != "window":
		return
	scheduler.cancel_tag(_slit_tag())
	scheduler.schedule_at(maxf(_get_scheduler_tick(), deadline), _resolve_slit_window.bind(deadline), _slit_tag())


func _resolve_slit_window(expected_deadline: float) -> void:
	if _slit_phase != "window" or not is_equal_approx(_slit_window_until, expected_deadline):
		return
	_update_concealment()
	_slit_window_until = -1.0
	if _any_party_in_radius(HIDE_SLIT_POS, STATION_RADIUS):
		_slit_phase = "safe"
		_last_outcome = "slit_held"
		_show_message("The song ends with someone physically inside the slit; the sentries pass.", 1.6)
		_set_preview_step("refuge_run_spot_ready")
		_publish_refuge_authority()
	else:
		_slit_phase = "failed"
		_fail("slit_window_closed_exposed")
	_update_concealment()
	_update_visual_state()
	_apply_refuge_interaction_presenters()


func _arm_spot_probe(deadline: float) -> void:
	var scheduler = _get_scheduler()
	if scheduler == null or _spot_phase != "sweeping":
		return
	scheduler.cancel_tag(_spot_tag())
	scheduler.schedule_at(maxf(_get_scheduler_tick(), deadline), _probe_spot_sweep.bind(deadline), _spot_tag())


func _probe_spot_sweep(expected_tick: float) -> void:
	if _spot_phase != "sweeping" or not is_equal_approx(_spot_probe_tick, expected_tick):
		return
	_update_concealment()
	if _sweep_acquires_exposed_target():
		_spot_phase = "failed"
		_spot_sweep_until = -1.0
		_spot_probe_tick = -1.0
		_fail("spot_sentry_acquired_target")
		_update_concealment()
		_update_visual_state()
		return
	if expected_tick >= _spot_sweep_until - 0.000001:
		_spot_phase = "safe"
		_spot_sweep_until = -1.0
		_spot_probe_tick = -1.0
		_exit_rest_phase = "ready"
		_last_outcome = "spot_sweep_evaded"
		_show_message("No sentry acquired a target. The sweep passes.", 1.4)
		_set_preview_step("refuge_run_exit")
		_apply_refuge_interaction_presenters()
		_publish_refuge_authority()
		_update_concealment()
		_update_visual_state()
		return
	_spot_probe_tick = minf(_spot_sweep_until, expected_tick + SPOT_PROBE_INTERVAL)
	_arm_spot_probe(_spot_probe_tick)
	_publish_refuge_authority()


func _sweep_acquires_exposed_target() -> bool:
	var gs = _get_game_state()
	if gs == null:
		return false
	for char_id in PARTY_IDS:
		if not gs.characters.has(char_id) or gs.is_downed(char_id) or gs.is_character_hidden(char_id):
			continue
		for enemy in _refuge_enemies():
			if enemy.has_method("engage_target") and bool(enemy.engage_target(char_id)):
				return true
	# A sentry that already owns an exposed party target is equally real acquisition.
	for enemy in _refuge_enemies():
		var target_id := str(enemy._current_target_id)
		if target_id in PARTY_IDS and gs.characters.has(target_id) and not gs.is_character_hidden(target_id):
			return true
	return false


func _slit_tag() -> String:
	return "refuge_run_slit:%s" % refuge_authority_key().sha256_text().substr(0, 12)


func _spot_tag() -> String:
	return "refuge_run_spot:%s" % refuge_authority_key().sha256_text().substr(0, 12)


func _cancel_refuge_callbacks() -> void:
	var scheduler = _get_scheduler()
	if scheduler != null:
		scheduler.cancel_tag(_slit_tag())
		scheduler.cancel_tag(_spot_tag())
		scheduler.cancel_tag(_exit_rest_tag())
		scheduler.cancel_tag(_spatial_authority_tag())


# --- Portable chunk authority ---

func refuge_authority_key() -> String:
	return "runtime:refuge_run:%s" % (chunk_name if chunk_name != "" else "refuge_run")


func _refuge_authority_state() -> Dictionary:
	return {
		"version": REFUGE_AUTHORITY_VERSION,
		"refuge_id": refuge_authority_key(),
		"route_phase": _route_phase,
		"route_choice": _route_choice,
		"route_commit_actor": _route_commit_actor,
		"route_commit_position": _route_commit_position.duplicate(),
		"last_outcome": _last_outcome,
		"hazard_taken": _hazard_taken,
		"slit_phase": _slit_phase,
		"slit_deadline": _slit_window_until,
		"spot_phase": _spot_phase,
		"spot_deadline": _spot_sweep_until,
		"spot_probe_tick": _spot_probe_tick,
		"shelter_reached": _shelter_reached,
		"exit_rest_phase": _exit_rest_phase,
		"exit_rest_members": PARTY_IDS.duplicate(),
		"exit_rest_commit_tick": _exit_rest_commit_tick,
		"exit_rest_commit_day": _exit_rest_commit_day,
		"exit_rest_before_atp": _exit_rest_before_atp.duplicate(true),
		"spatial_authority_epoch": _spatial_authority_epoch,
		"next_spatial_authority_tick": _next_spatial_authority_tick,
	}


func _baseline_refuge_authority_state() -> Dictionary:
	return {
		"version": REFUGE_AUTHORITY_VERSION,
		"refuge_id": refuge_authority_key(),
		"route_phase": "briefing",
		"route_choice": "",
		"route_commit_actor": "",
		"route_commit_position": [],
		"last_outcome": "",
		"hazard_taken": false,
		"slit_phase": "ready",
		"slit_deadline": -1.0,
		"spot_phase": "ready",
		"spot_deadline": -1.0,
		"spot_probe_tick": -1.0,
		"shelter_reached": false,
		"exit_rest_phase": "locked",
		"exit_rest_members": PARTY_IDS.duplicate(),
		"exit_rest_commit_tick": -1.0,
		"exit_rest_commit_day": 0,
		"exit_rest_before_atp": {},
		"spatial_authority_epoch": _spatial_authority_epoch,
		"next_spatial_authority_tick": _next_spatial_authority_tick,
	}


func _valid_refuge_authority(raw: Variant) -> bool:
	if not raw is Dictionary:
		return false
	var saved := raw as Dictionary
	var version := int(saved.get("version", 0))
	var slit_phase := str(saved.get("slit_phase", ""))
	var spot_phase := str(saved.get("spot_phase", ""))
	var route_phase := str(saved.get("route_phase", ""))
	var route_choice := str(saved.get("route_choice", ""))
	var base_valid := version in [1, 2, 3, REFUGE_AUTHORITY_VERSION] \
		and str(saved.get("refuge_id", "")) == refuge_authority_key() \
		and route_phase in VALID_ROUTE_PHASES \
		and ((route_phase == "briefing" and route_choice == "") \
			or (route_phase != "briefing" and route_choice in ["north", "south"])) \
		and slit_phase in VALID_SLIT_PHASES \
		and spot_phase in VALID_SPOT_PHASES \
		and (slit_phase != "window" or float(saved.get("slit_deadline", -1.0)) >= 0.0) \
		and (spot_phase != "sweeping" or (float(saved.get("spot_deadline", -1.0)) >= 0.0 \
			and float(saved.get("spot_probe_tick", -1.0)) >= 0.0))
	if not base_valid or version == 1:
		return base_valid
	var exit_phase := str(saved.get("exit_rest_phase", ""))
	var members_v: Variant = saved.get("exit_rest_members", null)
	var before_v: Variant = saved.get("exit_rest_before_atp", null)
	var shelter_reached := bool(saved.get("shelter_reached", false))
	var exit_valid := exit_phase in VALID_EXIT_REST_PHASES \
		and members_v is Array and (members_v as Array) == PARTY_IDS \
		and (shelter_reached == (exit_phase == "rested")) \
		and ((route_phase == "complete") == (exit_phase == "rested"))
	if exit_valid and exit_phase == "committing":
		exit_valid = spot_phase == "safe" \
			and float(saved.get("exit_rest_commit_tick", -1.0)) >= 0.0 \
			and int(saved.get("exit_rest_commit_day", 0)) >= 1 \
			and before_v is Dictionary
		if exit_valid:
			var before := before_v as Dictionary
			for char_id in PARTY_IDS:
				if not before.has(char_id) or float(before[char_id]) < 1.0:
					exit_valid = false
	elif exit_valid:
		exit_valid = is_equal_approx(
			float(saved.get("exit_rest_commit_tick", -1.0)), -1.0) \
			and before_v is Dictionary and (before_v as Dictionary).is_empty()
	if exit_valid and spot_phase != "safe" and route_phase != "complete":
		exit_valid = exit_phase == "locked"
	if exit_valid and spot_phase == "safe" and route_phase == "underway":
		exit_valid = exit_phase in ["ready", "committing"]
	if exit_valid and version >= 3:
		var route_actor := str(saved.get("route_commit_actor", ""))
		var route_position_v: Variant = saved.get("route_commit_position", null)
		exit_valid = route_position_v is Array
		if exit_valid and route_phase == "briefing":
			exit_valid = route_actor == "" and (route_position_v as Array).is_empty()
		elif exit_valid:
			exit_valid = route_actor != "" and (
				(route_position_v as Array).size() == 3 or route_actor == "script")
	if exit_valid and version >= 4:
		var route_position := saved.get("route_commit_position", []) as Array
		if route_phase != "briefing":
			var committed_position := Vector3(
				float(route_position[0]), float(route_position[1]), float(route_position[2]))
			exit_valid = str(saved.get("route_commit_actor", "")) in PARTY_IDS \
				and committed_position.is_finite() \
				and _route_for_position(committed_position) == route_choice
		var epoch := float(saved.get("spatial_authority_epoch", -1.0))
		var next_tick := float(saved.get("next_spatial_authority_tick", -1.0))
		exit_valid = exit_valid and is_finite(epoch) and epoch >= 0.0 \
			and is_finite(next_tick) and next_tick > _get_scheduler_tick()
	return exit_valid


func _initialize_refuge_authority() -> void:
	if _refuge_authority_initialized:
		return
	var gs = _get_game_state()
	if gs == null or not gs.has_method("get_world_state"):
		return
	_refuge_authority_initialized = true
	_restart_spatial_authority()
	_refuge_authority_baseline = _baseline_refuge_authority_state()
	var raw: Variant = gs.get_world_state(refuge_authority_key(), null)
	if _valid_refuge_authority(raw):
		_restore_refuge_authority(raw as Dictionary)
	else:
		_publish_refuge_authority()


func _publish_refuge_authority() -> void:
	if _restoring_refuge_authority:
		return
	var gs = _get_game_state()
	if gs != null and gs.has_method("set_world_state"):
		gs.set_world_state(refuge_authority_key(), _refuge_authority_state())


func on_game_state_snapshot_restored() -> void:
	super.on_game_state_snapshot_restored()
	_cancel_refuge_callbacks()
	_refuge_authority_initialized = true
	if _refuge_authority_baseline.is_empty():
		_refuge_authority_baseline = _baseline_refuge_authority_state()
	var gs = _get_game_state()
	var raw: Variant = gs.get_world_state(refuge_authority_key(), null) \
		if gs != null and gs.has_method("get_world_state") else null
	if not _valid_refuge_authority(raw):
		var baseline := _refuge_authority_baseline.duplicate(true)
		if gs != null and gs.has_method("set_world_state"):
			gs.set_world_state(refuge_authority_key(), baseline)
		_restore_refuge_authority(baseline)
		return
	_restore_refuge_authority(raw as Dictionary)


func _restore_refuge_authority(saved: Dictionary) -> void:
	_restoring_refuge_authority = true
	_cancel_refuge_callbacks()
	var saved_version := int(saved.get("version", REFUGE_AUTHORITY_VERSION))
	var normalized := saved_version != REFUGE_AUTHORITY_VERSION
	_route_phase = str(saved.get("route_phase", "briefing"))
	_route_choice = str(saved.get("route_choice", ""))
	if saved_version >= 3:
		_route_commit_actor = str(saved.get("route_commit_actor", ""))
		_route_commit_position = (saved.get("route_commit_position", []) as Array).duplicate()
	else:
		_route_commit_actor = "script" if _route_choice != "" else ""
		_route_commit_position = []
	_last_outcome = str(saved.get("last_outcome", ""))
	_hazard_taken = bool(saved.get("hazard_taken", false))
	_slit_phase = str(saved.get("slit_phase", "ready"))
	_slit_window_until = float(saved.get("slit_deadline", -1.0)) if _slit_phase == "window" else -1.0
	_spot_phase = str(saved.get("spot_phase", "ready"))
	_spot_sweep_until = float(saved.get("spot_deadline", -1.0)) if _spot_phase == "sweeping" else -1.0
	_spot_probe_tick = float(saved.get("spot_probe_tick", -1.0)) if _spot_phase == "sweeping" else -1.0
	if saved_version >= 2:
		_shelter_reached = bool(saved.get("shelter_reached", false))
		_exit_rest_phase = str(saved.get("exit_rest_phase", "locked"))
		_exit_rest_commit_tick = float(saved.get("exit_rest_commit_tick", -1.0))
		_exit_rest_commit_day = int(saved.get("exit_rest_commit_day", 0))
		_exit_rest_before_atp = (
			saved.get("exit_rest_before_atp", {}) as Dictionary).duplicate(true)
	else:
		# Version 1 could mark a glowing pad complete without shelter/rest authority. Preserve the
		# earned slit/spot solve, but retract that unsupported endpoint so it can be rested truthfully.
		if _route_phase == "complete":
			_route_phase = "underway"
		_shelter_reached = false
		_exit_rest_phase = "ready" if _spot_phase == "safe" else "locked"
		_clear_exit_rest_context()
	if _route_phase != "briefing" and not _saved_route_body_receipt_is_valid(
			_route_choice, _route_commit_actor, _route_commit_position):
		# Older helpers could remotely select a route with actor="script" and no body position.
		# That history has no physical provenance, so retract it and every dependent future.
		_route_phase = "briefing"
		_route_choice = ""
		_route_commit_actor = ""
		_route_commit_position.clear()
		_slit_phase = "ready"
		_slit_window_until = -1.0
		_spot_phase = "ready"
		_spot_sweep_until = -1.0
		_spot_probe_tick = -1.0
		_shelter_reached = false
		_exit_rest_phase = "locked"
		_clear_exit_rest_context()
		normalized = true
	var now := _get_scheduler_tick()
	if saved_version >= 4:
		_spatial_authority_epoch = float(saved.get("spatial_authority_epoch", -1.0))
		_next_spatial_authority_tick = float(saved.get("next_spatial_authority_tick", -1.0))
	else:
		_spatial_authority_epoch = now
		_next_spatial_authority_tick = FixedCadenceScript.next_strict_tick(
			_spatial_authority_epoch, SPATIAL_AUTHORITY_INTERVAL, now)
	if not is_finite(_spatial_authority_epoch) or _spatial_authority_epoch < 0.0 \
			or not is_finite(_next_spatial_authority_tick) \
			or _next_spatial_authority_tick <= now:
		_spatial_authority_epoch = now
		_next_spatial_authority_tick = FixedCadenceScript.next_strict_tick(
			_spatial_authority_epoch, SPATIAL_AUTHORITY_INTERVAL, now)
		normalized = true
	_restoring_refuge_authority = false
	normalized = _reconcile_slit_from_flure() or normalized
	if _slit_phase == "window":
		if _slit_window_until <= now + 0.000001:
			_resolve_slit_window(_slit_window_until)
		else:
			_arm_slit_resolution(_slit_window_until)
	if _spot_phase == "sweeping":
		if _spot_probe_tick <= now + 0.000001:
			_probe_spot_sweep(_spot_probe_tick)
		else:
			_arm_spot_probe(_spot_probe_tick)
	if _exit_rest_phase == "committing":
		_arm_exit_rest_callback()
	_arm_spatial_authority(_next_spatial_authority_tick)
	_update_concealment()
	_update_visual_state()
	_apply_refuge_interaction_presenters()
	_set_preview_step(_step_for_refuge_phase())
	if normalized:
		_publish_refuge_authority()


func _saved_route_body_receipt_is_valid(
	route_id: String,
	actor_id: String,
	position_record: Array
) -> bool:
	if actor_id not in PARTY_IDS or position_record.size() != 3:
		return false
	var position := Vector3(
		float(position_record[0]), float(position_record[1]), float(position_record[2]))
	return position.is_finite() and _route_for_position(position) == route_id


## The Flure owns the effect clock. Refuge authority owns what the player proved with
## that clock. This closes both possible signal/save seams without inventing a second timer.
func _reconcile_slit_from_flure() -> bool:
	if _slit_flure == null or not is_instance_valid(_slit_flure):
		return false
	var effect: Dictionary = _slit_flure.get_effect_state()
	var effect_phase := str(effect.get("phase", FlureScript.PHASE_READY))
	var effect_deadline := float(effect.get("end_tick", -1.0))
	var report: Dictionary = effect.get("last_activation_report", {}) as Dictionary
	var pulled := int(report.get("pulled", 0))
	var changed := false
	if _route_phase == "underway" and _slit_phase == "ready" \
			and effect_phase == FlureScript.PHASE_ACTIVE and pulled > 0 \
			and effect_deadline >= _get_scheduler_tick():
		_slit_phase = "window"
		_slit_window_until = effect_deadline
		_last_outcome = "slit_window_restored_from_flure"
		changed = true
	elif _slit_phase == "window" and effect_phase == FlureScript.PHASE_ACTIVE \
			and effect_deadline >= 0.0:
		if not is_equal_approx(_slit_window_until, effect_deadline):
			_slit_window_until = effect_deadline
			changed = true
	elif _slit_phase == "window" and _slit_window_until > _get_scheduler_tick() + 0.000001:
		# A future refuge window with no matching active flower is unsupported future state.
		_slit_phase = "ready"
		_slit_window_until = -1.0
		_last_outcome = "slit_window_retracted_without_flure"
		changed = true
	return changed


func _step_for_refuge_phase() -> String:
	if _route_phase == "complete": return "refuge_run_complete"
	if _route_phase == "failed": return "refuge_run_failed"
	if _spot_phase == "safe": return "refuge_run_exit"
	if _spot_phase == "sweeping": return "refuge_run_spot"
	if _slit_phase == "safe": return "refuge_run_spot_ready"
	if _slit_phase == "window": return "refuge_run_slit"
	if _route_choice != "": return "refuge_run_%s" % _route_choice
	return "refuge_run_briefing"

# --- Helpers ---

func _vector3_record(value: Vector3) -> Array:
	return [value.x, value.y, value.z] if value.is_finite() else []


func _actor_label(actor_id: String) -> String:
	return actor_id.capitalize() if actor_id in PARTY_IDS else "The party"


func _route_for_position(position: Vector3) -> String:
	if not position.is_finite() \
			or position.x < ROUTE_COMMIT_MIN_X or position.x > ROUTE_COMMIT_MAX_X:
		return ""
	if absf(position.z - NORTH_LANE_Z) <= ROUTE_COMMIT_RADIUS:
		return "north"
	if absf(position.z - SOUTH_LANE_Z) <= ROUTE_COMMIT_RADIUS:
		return "south"
	return ""


func _any_party_in_radius(center: Vector3, radius: float) -> bool:
	var gs = _get_game_state()
	for char_id in PARTY_IDS:
		if gs != null and (not gs.characters.has(char_id) or gs.is_downed(char_id)):
			continue
		if _position_in_radius(_get_character_position(char_id), center, radius):
			return true
	return false

func _all_party_in_radius(center: Vector3, radius: float) -> bool:
	var gs = _get_game_state()
	var any := false
	for char_id in PARTY_IDS:
		if gs != null and not gs.characters.has(char_id):
			continue
		if gs != null and gs.is_downed(char_id):
			return false
		any = true
		var pos := _get_character_position(char_id)
		if not _position_in_radius(pos, center, radius):
			return false
	return any


func _position_in_radius(position: Vector3, center: Vector3, radius: float) -> bool:
	return Vector2(position.x - center.x, position.z - center.z).length() <= radius


## A refuge is authored sanctuary, not a completion marker: a registered footprint, three-sided
## enclosure, warm light, and (at the exit) the exact-trio canonical rest interaction.
func _build_refuge_shelter(
	pos: Vector3,
	label: String,
	color: Color,
	is_exit: bool
) -> void:
	var pad: MeshInstance3D
	if is_exit:
		pad = _add_authored_shelter_region(self, pos, SHELTER_SIZE)
		_exit_shelter_interactable = _add_interactable(
			self,
			"RefugeExitRest",
			"Rest with the full party at the exit shelter",
			pos,
			"REST PARTY",
			"",
			1.2,
			true,
			2.5,
			Interactable.InteractableType.HOLD_ACTION)
		_exit_shelter_interactable.set_meta(
			"interaction_activation_contract", "proximity_rest")
		_exit_shelter_interactable.set_meta("authored_shelter_pad", pad)
		_exit_shelter_interactable.set("description", "Rest the full party at the exit shelter")
		_exit_shelter_interactable.set(
			"consequence_preview", "The exact conscious trio rests atomically")
		_exit_shelter_interactable.set_pre_trigger_validator(_validate_exit_shelter_trigger)
		_exit_shelter_interactable.interacted.connect(
			reach_exit.bind(_exit_shelter_interactable))
	else:
		pad = _add_authored_shelter_region(self, pos, SHELTER_SIZE)
	if pad != null:
		pad.material_override = _make_material(color * 0.28, color, 0.32)

	var half := SHELTER_SIZE * 0.5
	var back_sign := 1.0 if is_exit else -1.0
	_add_box(
		self,
		pos + Vector3(back_sign * (half.x - 0.15), 1.35, 0.0),
		Vector3(0.3, 2.7, SHELTER_SIZE.y),
		Color(0.11, 0.12, 0.13))
	for side in [-1.0, 1.0]:
		_add_box(
			self,
			pos + Vector3(0.0, 1.35, side * (half.y - 0.15)),
			Vector3(SHELTER_SIZE.x, 2.7, 0.3),
			Color(0.11, 0.12, 0.13))
	_add_light(self, pos + Vector3(0.0, 2.1, 0.0), color, 1.8, 8.0)
	_add_label(self, label, pos + Vector3(0.0, 2.8, 0.0), color)
	if is_exit:
		_apply_refuge_interaction_presenters()


func _apply_refuge_interaction_presenters() -> void:
	if _slit_flure != null and is_instance_valid(_slit_flure):
		var flure_effect: Dictionary = _slit_flure.get_effect_state()
		var flure_ready := str(flure_effect.get("phase", FlureScript.PHASE_READY)) \
			== FlureScript.PHASE_READY
		var flure_enabled := _route_phase == "underway" and _slit_phase == "ready" \
			and flure_ready
		if _slit_flure.is_interaction_enabled() != flure_enabled:
			_slit_flure.set_interaction_enabled(flure_enabled)
	if _spot_sweep_interactable != null and is_instance_valid(_spot_sweep_interactable):
		var spot_enabled := _route_phase == "underway" and _slit_phase == "safe" \
			and _spot_phase == "ready"
		_spot_sweep_interactable.restore_one_shot_presenter(
			_spot_phase != "ready", spot_enabled)
	_apply_exit_shelter_presenter()


func _apply_exit_shelter_presenter() -> void:
	if _exit_shelter_interactable == null or not is_instance_valid(_exit_shelter_interactable):
		return
	var enabled := _route_phase == "underway" and _slit_phase == "safe" \
		and _spot_phase == "safe" and _exit_rest_phase == "ready"
	_exit_shelter_interactable.restore_one_shot_presenter(
		_exit_rest_phase in ["committing", "rested"], enabled)

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
