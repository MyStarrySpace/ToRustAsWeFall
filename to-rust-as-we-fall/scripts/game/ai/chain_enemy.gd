class_name ChainEnemy
extends Enemy

## HIDRA runtime: a segmented infrastructure mimic that lies along wires and cabling, then
## unspools into an anchored lunge. The legacy class name remains for scene compatibility.

# --- Segment configuration ---
@export var segment_count := 8
@export var segment_spacing := 0.3
@export var follow_speed := 8.0
@export var max_stretch := 0.5

# --- Segment state ---
var _segments: Array[MeshInstance3D] = []
var _segment_positions: Array[Vector3] = []
var _segment_mats: Array[StandardMaterial3D] = []

# --- Anchor constraint ---
var _anchor_pos := Vector3.ZERO  # Wall attachment point (tail stays here)
var _anchored := true            # Whether the chain is tethered to its anchor
const CHAIN_CONTACT_INTERVAL := 0.05
const CHAIN_CONTACT_RANGE := 0.6
var _chain_contact_next_tick := 0.0

# --- Overrides ---

func _ready() -> void:
	if display_name == "Entity":
		display_name = "Hidra"
	super._ready()

func _build_visual() -> void:
	var body_color := Color(0.08, 0.06, 0.05)
	var joint_color := Color(0.25, 0.08, 0.04)

	for i in range(segment_count):
		var seg := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.06
		cap.height = segment_spacing * 0.8
		seg.mesh = cap
		var mat := StandardMaterial3D.new()
		mat.albedo_color = body_color if i % 2 == 0 else joint_color
		mat.metallic = 0.6
		mat.roughness = 0.3
		seg.material_override = mat
		add_child(seg)
		_segments.append(seg)
		_segment_mats.append(mat)

	_segment_positions.clear()
	for i in range(segment_count):
		_segment_positions.append(global_position - Vector3(0, 0, i * segment_spacing))
	_anchor_pos = _segment_positions[segment_count - 1]
	_anchored = true

	_eye_left = _make_eye(Vector3(-0.05, 0.0, 0.08))
	_eye_right = _make_eye(Vector3(0.05, 0.0, 0.08))

func _set_mesh_color(c: Color) -> void:
	for mat in _segment_mats:
		mat.albedo_color = c

func _process(delta: float) -> void:
	# Segment meshes below are presentation-only smoothing. Gameplay contact is sampled on the
	# scheduler from an analytic head/anchor shape, so render FPS cannot add or remove hits.
	super._process(delta)

	if _segments.is_empty():
		return

	var spd := 1.0
	var scheduler := _get_scheduler()
	if scheduler:
		spd = scheduler.get_speed()
	if scheduler and scheduler.is_paused():
		_apply_segment_visuals()
		return

	var lead := global_position

	var max_reach: float = segment_count * segment_spacing
	if _anchored:
		var anchor_dist := lead.distance_to(_anchor_pos)
		if anchor_dist > max_reach:
			var pull_dir := (_anchor_pos - lead).normalized()
			lead = _anchor_pos - pull_dir * max_reach
			global_position = lead

	_segment_positions[0] = lead

	var effective_speed := follow_speed * delta * spd
	for i in range(1, segment_count):
		var prev_pos: Vector3 = _segment_positions[i - 1]
		var curr_pos: Vector3 = _segment_positions[i]
		var to_prev := prev_pos - curr_pos
		var dist := to_prev.length()

		if dist < 0.001:
			continue

		var dir := to_prev.normalized()
		var desired := prev_pos - dir * segment_spacing

		_segment_positions[i] = curr_pos.lerp(desired, clampf(effective_speed, 0.0, 1.0))

		var new_dist := _segment_positions[i - 1].distance_to(_segment_positions[i])
		if new_dist > max_stretch:
			var snap_dir := (_segment_positions[i] - _segment_positions[i - 1]).normalized()
			_segment_positions[i] = _segment_positions[i - 1] + snap_dir * max_stretch

	if _anchored:
		_segment_positions[segment_count - 1] = _anchor_pos
		# Rope constraint: pull each link back toward the anchored tail so the chain stays continuous
		# (no link over max_stretch) AND its tail stays pinned, regardless of frame load. The per-frame
		# lerp above provides smoothing; this backward pass enforces the hard distance constraint, so a
		# heavy frame can't leave the chain transiently over-stretched between two checks.
		for i in range(segment_count - 2, 0, -1):
			var anchorward := _segment_positions[i + 1]
			var here := _segment_positions[i]
			var gap := anchorward.distance_to(here)
			if gap > max_stretch and gap > 0.0001:
				var pull := (here - anchorward).normalized() * max_stretch
				_segment_positions[i] = anchorward + pull

	_apply_segment_visuals()

func _apply_segment_visuals() -> void:
	for i in range(_segments.size()):
		if i >= _segment_positions.size():
			break
		var seg := _segments[i]
		seg.global_position = _segment_positions[i]

		if i + 1 < _segment_positions.size():
			var dir := _segment_positions[i + 1] - _segment_positions[i]
			if dir.length() > 0.01:
				seg.look_at(_segment_positions[i] + dir, Vector3.UP)
		elif i > 0:
			var dir := _segment_positions[i] - _segment_positions[i - 1]
			if dir.length() > 0.01:
				seg.look_at(_segment_positions[i] + dir, Vector3.UP)

	if get_state() == "idle" or get_state() == "patrol":
		var t := Time.get_ticks_msec() * 0.001  # @rendering_only — idle breathing animation
		for i in range(_segments.size()):
			_segments[i].position.y += sin(t + i * 0.5) * 0.01


# --- Scheduler-authoritative chain contact / save authority ---

func _begin_lunge() -> void:
	super._begin_lunge()
	if _charging and get_state() == "charge" and not _charge_hit:
		_arm_chain_contact_tick()


func _arm_chain_contact_tick(absolute_tick := -1.0) -> void:
	var scheduler := _get_scheduler()
	if scheduler == null or get_state() != "charge" or not _charging or _charge_hit:
		_chain_contact_next_tick = 0.0
		return
	var now := float(scheduler.get_current_tick())
	var deadline := float(absolute_tick)
	if deadline < 0.0:
		deadline = now + CHAIN_CONTACT_INTERVAL
	deadline = maxf(now + 0.000001, deadline)
	_chain_contact_next_tick = deadline
	scheduler.schedule_at(
		deadline,
		_on_chain_contact_tick.bind(deadline),
		_state_tag)
	_publish_enemy_authority()


func _on_chain_contact_tick(expected_tick: float) -> void:
	if not is_equal_approx(_chain_contact_next_tick, expected_tick):
		return
	_chain_contact_next_tick = 0.0
	if get_state() != "charge" or not _charging or _charge_hit:
		_publish_enemy_authority()
		return
	for segment_position in _authoritative_chain_positions():
		for target_id in _detection_targets:
			var target_position := _charge_target_world(target_id)
			if target_position == Vector3.INF \
					or segment_position.distance_to(target_position) >= CHAIN_CONTACT_RANGE:
				continue
			# The shared strike path owns dodge, sanctuary, downed checks, damage, and deduplication.
			if _resolve_strike(target_id):
				_end_charge()
				return
	if get_state() == "charge" and _charging and not _charge_hit:
		_arm_chain_contact_tick(expected_tick + CHAIN_CONTACT_INTERVAL)


## Gameplay collision is a pure function of scheduler-authoritative head position plus saved anchor
## state. The visually smoothed `_segment_positions` never participate in a hit decision.
func _authoritative_chain_positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	if segment_count <= 0:
		return result
	var head := _self_pos()
	if segment_count == 1:
		result.append(head)
		return result
	if _anchored:
		for i in range(segment_count):
			result.append(head.lerp(_anchor_pos, float(i) / float(segment_count - 1)))
		return result
	var away_from_tail := head - _anchor_pos
	var axis := away_from_tail.normalized() if away_from_tail.length_squared() > 0.000001 \
		else Vector3.FORWARD
	for i in range(segment_count):
		result.append(head - axis * segment_spacing * float(i))
	return result


func _publish_enemy_authority() -> void:
	super._publish_enemy_authority()
	if _restoring_enemy_authority or not _enemy_authority_initialized \
			or game_state == null or not game_state.has_method("set_world_state"):
		return
	var key := _enemy_authority_key()
	var saved: Variant = game_state.get_world_state(key, {})
	if not (saved is Dictionary) \
			or int(saved.get("version", 0)) != ENEMY_AUTHORITY_VERSION:
		return
	var record := (saved as Dictionary).duplicate(true)
	record["chain"] = {
		"anchor_pos": _vec3_to_data(_anchor_pos),
		"anchored": _anchored,
		"next_contact_tick": _chain_contact_next_tick,
	}
	game_state.set_world_state(key, record)


func on_game_state_snapshot_restored() -> void:
	super.on_game_state_snapshot_restored()
	_chain_contact_next_tick = 0.0
	if not _has_saved_enemy_authority():
		return
	var saved: Dictionary = game_state.get_world_state(_enemy_authority_key(), {})
	var chain: Dictionary = saved.get("chain", {})
	if not chain.is_empty():
		_anchor_pos = _vec3_from_data(chain.get("anchor_pos", []), _anchor_pos)
		_anchored = bool(chain.get("anchored", true))
		_chain_contact_next_tick = float(chain.get("next_contact_tick", 0.0))
	_sync_chain_visual_to_authority()
	if get_state() == "charge" and _charging and not _charge_hit:
		var scheduler := _get_scheduler()
		var deadline := _chain_contact_next_tick
		if scheduler != null and deadline <= float(scheduler.get_current_tick()):
			deadline = float(scheduler.get_current_tick()) + CHAIN_CONTACT_INTERVAL
		_arm_chain_contact_tick(deadline)


func _sync_chain_visual_to_authority() -> void:
	var authoritative := _authoritative_chain_positions()
	_segment_positions.clear()
	_segment_positions.append_array(authoritative)
	_apply_segment_visuals()

# --- Public helpers ---

## Set initial segment positions. Last point becomes the anchor.
func set_wall_line(start: Vector3, direction: Vector3) -> void:
	_segment_positions.clear()
	for i in range(segment_count):
		_segment_positions.append(start + direction.normalized() * (i * segment_spacing))
	_anchor_pos = _segment_positions[segment_count - 1]
	_anchored = true
	_publish_enemy_authority()

## Detach from the anchor.
func detach() -> void:
	_anchored = false
	_publish_enemy_authority()

## Attach to an anchor position.
func anchor_to(pos: Vector3) -> void:
	_anchor_pos = pos
	_anchored = true
	_sync_chain_visual_to_authority()
	_publish_enemy_authority()

## Maximum distance the head can reach from the anchor.
func get_max_reach() -> float:
	return segment_count * segment_spacing

## Get segment world positions.
func get_segment_positions() -> Array[Vector3]:
	return _segment_positions.duplicate()

## Return target_id if any segment is in contact range.
func check_segment_contact(contact_range := 0.6) -> String:
	for seg_pos in _segment_positions:
		for target_id in _detection_targets:
			var target_node := _find_character_node(target_id)
			if not target_node:
				continue
			if seg_pos.distance_to(target_node.global_position) < contact_range:
				return target_id
	return ""
