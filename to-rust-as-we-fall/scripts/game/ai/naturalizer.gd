class_name Naturalizer
extends Enemy

## NATURALIZER (fauna_roster L34): institutional enforcement — fixed-route scan patrol, a lethal
## contact strike on whatever its scan flags, the granule-pack tell before it fires. Chase canon
## (chase_scene_framework.md): PROTOCOL HESITATION around iron-feeding fauna — inside a registered
## hesitation zone (a Chelator cluster's apron) it moves at a crawl, which is the chase's
## signature environmental lever. Zones are checked on a scheduler cadence (never per-frame), and
## the slow is a real logged speed change — replay and fast-forward safe like every other move.

const HESITATION_FACTOR := 0.45
const HESITATION_POLL := 0.4
const NATURALIZER_AUTHORITY_VERSION := 1
const NATURALIZER_AUTHORITY_PREFIX := "runtime:naturalizer:"
const _RESTORE_POLL_EPSILON := 0.000001

var _hesitation_zones: Array = []   # [{pos: Vector3, radius: float}]
var _hesitating := false
var _nat_base_speed := 0.0
var _hesitation_poll_deadline := -1.0
var _naturalizer_authority_initialized := false
var _restoring_naturalizer_authority := false
var _scan_ring: MeshInstance3D

func _ready() -> void:
	# the clean enforcement white is the BASE color (state repaints return to it)
	color = Color(0.92, 0.94, 0.96)
	# CONTACT strike (fauna_roster: "lethal contact-strike"): the granule tell is SHORT — a
	# Naturalizer does not do the windup-lunge dance that whiffs against a runner. Against a
	# fleeing target the cycle must close, or sprint-only play beats the chase (the probe's
	# finding: the default 0.8s windup + 1.2s recover let a straight runner stay ahead forever).
	windup_duration = 0.35
	recover_duration = 0.55
	charge_speed = 10.0
	attack_range = 2.4
	super._ready()
	_nat_base_speed = move_speed

func add_hesitation_zone(pos: Vector3, radius: float) -> void:
	var safe_radius := maxf(0.0, radius)
	for zone_v in _hesitation_zones:
		var zone := zone_v as Dictionary
		if (zone.get("pos", Vector3.ZERO) as Vector3).is_equal_approx(pos) \
				and is_equal_approx(float(zone.get("radius", 0.0)), safe_radius):
			# Scene wiring is replayed when a fresh presenter is built. The saved zone is already
			# authoritative, so the duplicate authored call must not restart its cadence.
			return
	_hesitation_zones.append({"pos": pos, "radius": safe_radius})
	_arm_hesitation_poll()
	_publish_naturalizer_authority()

func activate() -> void:
	var had_saved_authority := _has_saved_naturalizer_authority()
	super.activate()
	# Enemy.activate() invokes the virtual restore hook when it finds a saved enemy phase. Avoid
	# publishing scene defaults over that record before the hook has rebuilt this subclass too.
	if had_saved_authority:
		if not _naturalizer_authority_initialized:
			_restore_naturalizer_authority()
		return
	_naturalizer_authority_initialized = true
	_publish_naturalizer_authority()
	_arm_hesitation_poll()

func _hes_tag() -> String:
	return "nat_hes_%s" % char_id

func _arm_hesitation_poll() -> void:
	var sched = _get_scheduler()
	if sched == null or _hesitation_zones.is_empty():
		return
	_schedule_hesitation_poll_at(float(sched.get_current_tick()) + HESITATION_POLL)

func _schedule_hesitation_poll_at(deadline: float) -> void:
	var sched = _get_scheduler()
	if sched == null or _hesitation_zones.is_empty():
		_hesitation_poll_deadline = -1.0
		_publish_naturalizer_authority()
		return
	# The native scheduler removes a fired handle from its live set before invoking us, but retains
	# that stale handle in the tag index. Clearing the tag before scheduling its successor keeps the
	# recurring index bounded and also retracts any accidental duplicate poll.
	sched.cancel_tag(_hes_tag())
	_hesitation_poll_deadline = deadline
	var remaining := maxf(_RESTORE_POLL_EPSILON,
		deadline - float(sched.get_current_tick()))
	sched.schedule_after(remaining,
		_run_hesitation_poll.bind(deadline), _hes_tag())
	_publish_naturalizer_authority()

func _run_hesitation_poll(expected_deadline: float) -> void:
	# An idempotent restore or a newly-authored zone supersedes the old callback. Tag cancellation is
	# the first guard; the absolute-deadline token also makes stale callbacks harmless by construction.
	if _hesitation_poll_deadline < 0.0 \
			or not is_equal_approx(_hesitation_poll_deadline, expected_deadline):
		return
	_hesitation_poll_deadline = -1.0
	_hesitation_poll()

func _hesitation_poll() -> void:
	if game_state != null and game_state.characters.has(char_id) and is_alive():
		var p: Vector3 = game_state.get_position(char_id)
		var inside := false
		for z_v in _hesitation_zones:
			var z := z_v as Dictionary
			var zp: Vector3 = z["pos"]
			if Vector2(p.x - zp.x, p.z - zp.z).length() <= float(z["radius"]):
				inside = true
				break
		if inside != _hesitating:
			_hesitating = inside
			game_state.change_move_speed(char_id,
				_nat_base_speed * HESITATION_FACTOR if inside else _nat_base_speed)
	var sched = _get_scheduler()
	if sched != null and not _hesitation_zones.is_empty() and is_alive():
		_schedule_hesitation_poll_at(
			float(sched.get_current_tick()) + HESITATION_POLL)
	else:
		_hesitation_poll_deadline = -1.0
		_publish_naturalizer_authority()

func is_hesitating() -> bool:
	return _hesitating

## Naturalizer's environmental lever is a separate gameplay phase layered over Enemy's FSM. It
## therefore owns a stable sibling record: scheduler snapshots restore clocks, never Callables.
func _naturalizer_authority_key() -> String:
	return NATURALIZER_AUTHORITY_PREFIX + char_id if char_id != "" else ""

func _has_saved_naturalizer_authority() -> bool:
	if game_state == null or not game_state.has_method("get_world_state"):
		return false
	var key := _naturalizer_authority_key()
	if key == "":
		return false
	var saved: Variant = game_state.get_world_state(key, {})
	return saved is Dictionary \
			and int(saved.get("version", 0)) == NATURALIZER_AUTHORITY_VERSION \
			and str(saved.get("char_id", char_id)) == char_id

func _publish_naturalizer_authority() -> void:
	if _restoring_naturalizer_authority or not _naturalizer_authority_initialized:
		return
	if game_state == null or not game_state.has_method("set_world_state"):
		return
	var key := _naturalizer_authority_key()
	if key == "":
		return
	var zone_data: Array = []
	for zone_v in _hesitation_zones:
		var zone := zone_v as Dictionary
		var pos: Vector3 = zone.get("pos", Vector3.ZERO)
		zone_data.append({
			"pos": [pos.x, pos.y, pos.z],
			"radius": maxf(0.0, float(zone.get("radius", 0.0))),
		})
	game_state.set_world_state(key, {
		"version": NATURALIZER_AUTHORITY_VERSION,
		"char_id": char_id,
		"hesitating": _hesitating,
		"base_speed": _nat_base_speed,
		"hesitation_zones": zone_data,
		"poll_armed": _hesitation_poll_deadline >= 0.0,
		"next_poll_tick": _hesitation_poll_deadline,
	})

func on_game_state_snapshot_restored() -> void:
	super.on_game_state_snapshot_restored()
	_restore_naturalizer_authority()


func _exit_tree() -> void:
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag(_hes_tag())
	_hesitation_poll_deadline = -1.0
	super._exit_tree()

func _restore_naturalizer_authority() -> void:
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag(_hes_tag())
	_hesitation_poll_deadline = -1.0
	if not _has_saved_naturalizer_authority():
		# Absence is authoritative during same-node rollback: zones and hesitation added after the
		# snapshot must disappear with their callbacks. GameState already restored the saved speed.
		_hesitation_zones.clear()
		_hesitating = false
		_naturalizer_authority_initialized = false
		return

	var saved: Dictionary = game_state.get_world_state(_naturalizer_authority_key(), {})
	_restoring_naturalizer_authority = true
	_hesitating = bool(saved.get("hesitating", false))
	_nat_base_speed = maxf(0.0, float(saved.get("base_speed", move_speed)))
	_hesitation_zones.clear()
	for zone_v in (saved.get("hesitation_zones", []) as Array):
		var zone := zone_v as Dictionary
		var pos_data: Array = zone.get("pos", [0.0, 0.0, 0.0])
		if pos_data.size() < 3:
			continue
		_hesitation_zones.append({
			"pos": Vector3(float(pos_data[0]), float(pos_data[1]), float(pos_data[2])),
			"radius": maxf(0.0, float(zone.get("radius", 0.0))),
		})
	if bool(saved.get("poll_armed", false)) and not _hesitation_zones.is_empty() and is_alive():
		var deadline := float(saved.get("next_poll_tick", -1.0))
		if deadline >= 0.0 and sched != null:
			_hesitation_poll_deadline = deadline
			var remaining := maxf(_RESTORE_POLL_EPSILON,
				deadline - float(sched.get_current_tick()))
			sched.schedule_after(remaining,
				_run_hesitation_poll.bind(deadline), _hes_tag())
	_restoring_naturalizer_authority = false
	_naturalizer_authority_initialized = true

## Clean white enforcement body + the rotating scanner ring (TASKS 20.6's read), cool blue lamps.
func _build_visual() -> void:
	super._build_visual()
	if _mesh != null and _mesh.material_override is StandardMaterial3D:
		var m := _mesh.material_override as StandardMaterial3D
		m.albedo_color = Color(0.92, 0.94, 0.96)
	_scan_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	_scan_ring.mesh = torus
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.55, 0.75, 1.0)
	rm.emission_enabled = true
	rm.emission = Color(0.55, 0.78, 1.0)
	rm.emission_energy_multiplier = 1.6
	_scan_ring.material_override = rm
	_scan_ring.position = Vector3(0, 1.1, 0)
	add_child(_scan_ring)

func _process(delta: float) -> void:
	super._process(delta)
	# @rendering_only — the scanner line sweep, pure cosmetics
	if _scan_ring != null and is_instance_valid(_scan_ring):
		_scan_ring.rotate_y(delta * 2.4)
