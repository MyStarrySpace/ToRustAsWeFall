class_name ChainEnemy
extends Enemy

## Chain-style segmented worm enemy. Looks like pipes and wires.
## One lead point (head) driven by GameState. Segments follow with
## spring-damped lerp. All segments deal contact damage during charge.
## Camouflages against wall infrastructure when idle.

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

# --- Overrides ---

func _build_visual() -> void:
	# Dark metallic color matching pipes — GDD: "almost black, rust-red joints"
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

	# Initialize segment positions trailing behind the spawn point
	_segment_positions.clear()
	for i in range(segment_count):
		_segment_positions.append(global_position - Vector3(0, 0, i * segment_spacing))
	_anchor_pos = _segment_positions[segment_count - 1]
	_anchored = true

	# Eyes on the head segment only
	_eye_left = _make_eye(Vector3(-0.05, 0.0, 0.08))
	_eye_right = _make_eye(Vector3(0.05, 0.0, 0.08))

func _set_mesh_color(c: Color) -> void:
	for mat in _segment_mats:
		mat.albedo_color = c

func _process(delta: float) -> void:
	# Check segment contact BEFORE parent (parent might end charge on head miss)
	if _charging and _state == "charge" and not _charge_hit:
		for seg_pos in _segment_positions:
			for target_id in _detection_targets:
				var target_node := _find_character_node(target_id)
				if not target_node:
					continue
				if seg_pos.distance_to(target_node.global_position) < 0.6:
					_charge_hit = true
					hit_target.emit(target_id, charge_damage)
					_end_charge()
					break
			if _charge_hit:
				break

	# Parent handles GameState position sync and charge movement
	super._process(delta)

	if _segments.is_empty():
		return

	# Get scheduler speed for pause/fast-forward
	var spd := 1.0
	var scheduler := _get_scheduler()
	if scheduler:
		spd = scheduler.get_speed()
	if scheduler and scheduler.is_paused():
		_apply_segment_visuals()
		return

	# Lead point is the enemy's global position (set by parent _process)
	var lead := global_position

	# Anchor constraint: clamp lead point to max reach from anchor
	var max_reach: float = segment_count * segment_spacing
	if _anchored:
		var anchor_dist := lead.distance_to(_anchor_pos)
		if anchor_dist > max_reach:
			var pull_dir := (_anchor_pos - lead).normalized()
			lead = _anchor_pos - pull_dir * max_reach
			global_position = lead

	# Head segment tracks the lead point
	_segment_positions[0] = lead

	# Each subsequent segment follows the one in front
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

		# Spring-damped follow
		_segment_positions[i] = curr_pos.lerp(desired, clampf(effective_speed, 0.0, 1.0))

		# Hard constraint: never stretch beyond max_stretch
		var new_dist := _segment_positions[i - 1].distance_to(_segment_positions[i])
		if new_dist > max_stretch:
			var snap_dir := (_segment_positions[i] - _segment_positions[i - 1]).normalized()
			_segment_positions[i] = _segment_positions[i - 1] + snap_dir * max_stretch

	# Pin the tail to the anchor while tethered
	if _anchored:
		_segment_positions[segment_count - 1] = _anchor_pos

	_apply_segment_visuals()

func _apply_segment_visuals() -> void:
	for i in range(_segments.size()):
		if i >= _segment_positions.size():
			break
		var seg := _segments[i]
		# Position relative to parent node
		seg.global_position = _segment_positions[i]

		# Rotate to face the next segment (or previous if last)
		if i + 1 < _segment_positions.size():
			var dir := _segment_positions[i + 1] - _segment_positions[i]
			if dir.length() > 0.01:
				seg.look_at(_segment_positions[i] + dir, Vector3.UP)
		elif i > 0:
			var dir := _segment_positions[i] - _segment_positions[i - 1]
			if dir.length() > 0.01:
				seg.look_at(_segment_positions[i] + dir, Vector3.UP)

	# Idle breathing: subtle position oscillation
	if _state == "idle" or _state == "patrol":
		var t := Time.get_ticks_msec() * 0.001
		for i in range(_segments.size()):
			_segments[i].position.y += sin(t + i * 0.5) * 0.01

# --- Public helpers ---

## Set initial segment positions along a wall line.
## The last segment becomes the anchor point. Call before activate().
func set_wall_line(start: Vector3, direction: Vector3) -> void:
	_segment_positions.clear()
	for i in range(segment_count):
		_segment_positions.append(start + direction.normalized() * (i * segment_spacing))
	# Anchor is the tail (last segment)
	_anchor_pos = _segment_positions[segment_count - 1]
	_anchored = true

## Detach from the wall anchor. Head moves freely, tail no longer pinned.
func detach() -> void:
	_anchored = false

## Re-anchor to a new position (e.g. after settling on a new wall).
func anchor_to(pos: Vector3) -> void:
	_anchor_pos = pos
	_anchored = true

## Maximum distance the head can reach from the anchor.
func get_max_reach() -> float:
	return segment_count * segment_spacing

## Get all segment world positions (for external collision checks).
func get_segment_positions() -> Array[Vector3]:
	return _segment_positions.duplicate()

## Check if any segment is within contact range of a target. Returns target_id or "".
func check_segment_contact(contact_range := 0.6) -> String:
	for seg_pos in _segment_positions:
		for target_id in _detection_targets:
			var target_node := _find_character_node(target_id)
			if not target_node:
				continue
			if seg_pos.distance_to(target_node.global_position) < contact_range:
				return target_id
	return ""
