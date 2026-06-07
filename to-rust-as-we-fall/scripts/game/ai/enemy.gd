class_name Enemy
extends Node3D

## Scheduler-driven enemy state, HP, detection, and charge attacks.
## Override _build_visual() for variants.

# --- Configuration ---
@export var display_name := "Entity"
@export var color := Color(0.4, 0.15, 0.1)
@export var max_hp := 50.0
@export var move_speed := 1.5
@export var detection_range := 6.0
@export var scan_interval := 0.5
@export var pursuit_update_interval := 0.8

@export var attack_range := 3.0
@export var roam_step_distance := 1.6  # how far a single roam hop travels
@export var roam_interval := 1.4       # scheduler ticks between roam hops
@export var windup_duration := 0.8
@export var charge_speed := 8.0
@export var charge_damage := 25.0
@export var charge_max_duration := 1.5
@export var recover_duration := 1.2
@export var iframe_duration := 1.0
@export var pursuit_rescan_delay := 4.0  # Seconds of pursuit before scanning for new targets

# --- GameState integration (set by scene before adding to tree) ---
var game_state: GameState
var char_id := ""

# --- State machine (reusable scheduler-driven FSM) ---
var _fsm: StateMachine
var _state_tag := ""
var _hp: float

# --- Detection ---
var _detection_targets: Array[String] = []
var _current_target_id := ""
var _alert_label: Label3D

# --- Patrol (authored routes) ---
var _patrol_waypoints: Array[Vector3] = []
var _patrol_index := 0

# --- Roam (undirected wander: cheap local hops, NEVER pathfinding) ---
var _roam_anchor := Vector3.ZERO
var _roam_radius := 0.0
var _roam_heading := Vector3(0.0, 0.0, -1.0)  # current wander direction
var _roam_seq := 0                            # deterministic hop counter (fast-forward invariant)

# --- Attack cycle ---
var _charge_target_pos := Vector3.ZERO
var _charging := false
var _charge_hit := false
# Charge position is derived from the scheduler tick (not wall-clock delta) so the
# hit lands at the same tick whether or not fast-forward is held.
var _charge_start_tick := 0.0
var _charge_start_pos := Vector3.ZERO

# --- Visual ---
var _mesh: MeshInstance3D
var _eye_left: OmniLight3D
var _eye_right: OmniLight3D
var _base_color: Color

signal damaged(amount: float, new_hp: float)
signal died()
signal target_spotted(target_id: String)
signal hit_target(target_id: String, damage: float)

func _ready() -> void:
	_hp = max_hp
	_base_color = color
	_state_tag = "enemy_%s" % name
	_build_visual()
	_build_fsm()

# --- Public API ---

## Start after game_state and char_id are set.
func activate() -> void:
	if get_state() == "dead":
		return
	if game_state and not game_state.detection_predicted.is_connected(_on_detection_predicted):
		game_state.detection_predicted.connect(_on_detection_predicted)
	_fsm.transition_to("idle")

## Set patrol waypoints (an AUTHORED route — pathfinds between waypoints to route around walls).
func set_patrol(waypoints: Array[Vector3]) -> void:
	_patrol_waypoints = waypoints
	_patrol_index = 0
	if get_state() != "dead":
		_fsm.transition_to("patrol")

## Begin lightweight roaming around `anchor` within `radius`. Roaming NEVER pathfinds: it's a local
## deterministic wander — short straight hops (command_move_to_pos), an anchor-pull at the circle's
## edge, and a cheap single-cell wall bounce on grid scenes — so a yard full of idle enemies costs
## almost nothing. Only an actual sighting promotes to pursuit, and ONLY pursuit pathfinds.
func set_roam(anchor: Vector3, radius: float) -> void:
	_roam_anchor = anchor
	_roam_radius = maxf(0.5, radius)
	_roam_seq = 0
	if get_state() != "dead":
		_fsm.transition_to("roam")

## Apply damage.
func take_damage(amount: float) -> void:
	if get_state() == "dead":
		return
	_hp = maxf(0.0, _hp - amount)
	damaged.emit(amount, _hp)
	if _hp <= 0:
		die()

## Kill immediately.
func die() -> void:
	_fsm.transition_to("dead")

func is_alive() -> bool:
	return _hp > 0

func get_state() -> String:
	return _fsm.current() if _fsm != null else ""

# --- State Machine Core (reusable StateMachine: tag-scoped scheduling + exit/enter hooks) ---

const ENEMY_STATES := ["idle", "roam", "patrol", "detecting", "alert", "pursuit", "windup", "charge", "recover", "dead"]

func _build_fsm() -> void:
	_fsm = StateMachine.new(_get_scheduler(), _state_tag)
	for state_name in ENEMY_STATES:
		_fsm.add_state(state_name, _enter_state.bind(state_name), _exit_state.bind(state_name))
	_fsm.start("idle")  # default state before activate() (idle's enter is a no-op)

## Force a state directly. Prefer letting the FSM drive transitions; this exists for external
## resets (showcase / test harnesses) that pin an enemy back to a known state.
func _change_state(new_state: String) -> void:
	if _fsm != null:
		_fsm.transition_to(new_state)

func _enter_state(state: String) -> void:
	match state:
		"idle":
			pass  # Detection via GameState prediction signal
		"roam":
			_set_eye_energy(0.5)
			_roam_step()
		"patrol":
			_patrol_next_waypoint()
		"detecting":
			pass  # Explicitly scanning for new targets after pursuit timeout
		"alert":
			_show_alert_on_target()
			_set_eye_energy(1.5)
			var scheduler := _get_scheduler()
			if scheduler:
				scheduler.schedule_after(1.0, _begin_pursuit, _state_tag)
		"pursuit":
			_set_eye_energy(2.0)
			_pursue_target()
			# Rescan after pursuit_rescan_delay.
			var sched := _get_scheduler()
			if sched and pursuit_rescan_delay > 0:
				sched.schedule_after(pursuit_rescan_delay, _begin_rescan, _state_tag)
		"detecting":
			# Listening for detection_predicted signal (same as idle)
			_set_eye_energy(0.6)
			_current_target_id = ""
		"windup":
			_stop_movement()
			_set_mesh_color(Color(0.9, 0.15, 0.1))
			_set_eye_energy(3.0)
			# Lock the target position at the moment of windup
			if _current_target_id != "" and game_state:
				_charge_target_pos = game_state.get_position(_current_target_id)
			var scheduler := _get_scheduler()
			if scheduler:
				scheduler.schedule_after(windup_duration, _begin_charge, _state_tag)
		"charge":
			_charging = true
			_charge_hit = false
			_charge_start_pos = global_position
			var scheduler := _get_scheduler()
			if scheduler:
				_charge_start_tick = scheduler.get_current_tick()
				# Predictive strike: schedule the hit for the contact tick. It lands for sure (the lunge
				# commits) unless the target dodges in the window — no per-frame distance check to whiff.
				var lunge_dist: float = Vector2(_charge_target_pos.x - _charge_start_pos.x,
					_charge_target_pos.z - _charge_start_pos.z).length()
				var contact_time: float = minf(lunge_dist / maxf(charge_speed, 0.1), charge_max_duration)
				scheduler.schedule_after(contact_time, _land_attack, _state_tag)
		"recover":
			_charging = false
			_stop_movement()
			_set_mesh_color(Color(0.2, 0.3, 0.7))
			_set_eye_energy(0.3)
			# Fade from blue back to normal color
			if _mesh and _mesh.material_override:
				var tween := create_tween()
				tween.tween_method(_set_mesh_color, Color(0.2, 0.3, 0.7), _base_color, recover_duration)
			var scheduler := _get_scheduler()
			if scheduler:
				scheduler.schedule_after(recover_duration, _resume_pursuit, _state_tag)
		"dead":
			_charging = false
			_stop_movement()
			_set_eye_energy(0.0)
			died.emit()
			_fade_out(1.5)

func _exit_state(state: String) -> void:
	match state:
		"roam":
			_stop_movement()
		"alert":
			_remove_alert_label()
		"pursuit":
			_stop_movement()
		"charge":
			_charging = false

# --- Detection (via GameState predictive signal) ---

func _on_detection_predicted(detector_id: String, target_id: String) -> void:
	if detector_id != char_id:
		return
	if target_id not in _detection_targets:
		return
	# Only respond to detections when in a scanning state (roaming enemies still see)
	if get_state() not in ["idle", "roam", "patrol", "detecting"]:
		return
	_current_target_id = target_id
	target_spotted.emit(target_id)
	_fsm.transition_to("alert")

# --- Alert ---

func _show_alert_on_target() -> void:
	_remove_alert_label()
	if _current_target_id == "" or not game_state:
		return
	var target_node := _find_character_node(_current_target_id)
	if not target_node:
		return
	_alert_label = Label3D.new()
	_alert_label.name = "AlertMark"
	_alert_label.text = "!"
	_alert_label.font_size = 72
	_alert_label.pixel_size = 0.012
	_alert_label.modulate = Color(1, 1, 1, 0.95)
	_alert_label.outline_modulate = Color(0, 0, 0, 0.6)
	_alert_label.outline_size = 5
	_alert_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_alert_label.position = Vector3(0, 1.8, 0)
	target_node.add_child(_alert_label)

func _remove_alert_label() -> void:
	if _alert_label and is_instance_valid(_alert_label):
		_alert_label.queue_free()
	_alert_label = null

# Pursuit, windup, charge, recover.

func _begin_pursuit() -> void:
	if get_state() != "alert":
		return
	_remove_alert_label()
	_fsm.transition_to("pursuit")

func _pursue_target() -> void:
	if get_state() != "pursuit" or _current_target_id == "" or not game_state:
		return
	var target_pos := game_state.get_position(_current_target_id)
	var dist := global_position.distance_to(target_pos)
	# Close enough to wind up.
	if dist < attack_range:
		_fsm.transition_to("windup")
		return
	# Otherwise keep chasing
	if game_state.characters.has(char_id):
		if game_state.grid:
			game_state.command_move_to_cell(char_id, game_state.grid.world_to_grid(target_pos))
		else:
			game_state.command_move_to_pos(char_id, target_pos)
	var scheduler := _get_scheduler()
	if scheduler:
		scheduler.schedule_after(pursuit_update_interval, _pursue_target, _state_tag)

func _begin_charge() -> void:
	if get_state() != "windup":
		return
	_fsm.transition_to("charge")

func _end_charge() -> void:
	if get_state() != "charge":
		return
	_fsm.transition_to("recover")

## The predicted strike fires here at the contact tick. It ALWAYS lands on the committed target unless
## that target is mid-dodge (dodge_roll, gated behind dodge_unlocked). On a hit it commits the lunge
## end to the data layer (so the body doesn't snap back next move), deals damage, and flinches the
## target. Then recover. Replaces the old per-frame distance check that could miss.
func _land_attack() -> void:
	if get_state() != "charge":
		return
	var tid := _current_target_id
	# Dodge window: if the target can roll (dodge_unlocked) and is set to auto-evade, it slips the
	# committed strike. With dodge locked (the default — not unlocked in every chunk), the hit lands.
	if tid != "" and game_state != null and game_state.has_method("dodge_roll") and game_state.characters.has(tid):
		var st: Dictionary = game_state.characters[tid].stats
		if bool(st.get("dodge_unlocked", false)) and bool(st.get("auto_dodge", false)) and not game_state.is_dodging(tid):
			var ap := global_position
			var tp := game_state.get_position(tid)
			var approach := Vector3(ap.x - tp.x, 0.0, ap.z - tp.z)
			var perp := Vector3(-approach.z, 0.0, approach.x)
			perp = perp.normalized() if perp.length_squared() > 0.001 else Vector3(1.0, 0.0, 0.0)
			game_state.dodge_roll(tid, perp)
	var dodged := tid != "" and game_state != null and game_state.has_method("is_dodging") and game_state.is_dodging(tid)
	if tid != "" and game_state != null and not dodged:
		_charge_hit = true
		# End ON the target so the strike connects, and COMMIT it so the next move starts from here.
		var contact := _charge_target_pos
		if game_state.characters.has(tid):
			contact = game_state.get_position(tid)
		global_position = Vector3(contact.x, global_position.y, contact.z)
		if game_state.has_method("snap_character_to") and game_state.characters.has(char_id):
			game_state.snap_character_to(char_id, contact)
		if game_state.has_method("adjust_stat") and game_state.characters.has(tid):
			game_state.adjust_stat(tid, "hp", -charge_damage)
		_flash_target(tid)
		hit_target.emit(tid, charge_damage)
	_fsm.transition_to("recover")

## Brief flinch on a struck character — a universal scale-punch on its node (cosmetic; any Node3D).
func _flash_target(target_id: String) -> void:
	var node := _find_character_node(target_id) as Node3D
	if node == null:
		return
	var base: Vector3 = node.scale
	var tween := create_tween()
	tween.tween_property(node, "scale", base * 1.25, 0.07)
	tween.tween_property(node, "scale", base, 0.18)

func _resume_pursuit() -> void:
	if get_state() != "recover":
		return
	_set_mesh_color(_base_color)
	_fsm.transition_to("pursuit")

func _begin_rescan() -> void:
	if get_state() != "pursuit":
		return
	_stop_movement()
	_fsm.transition_to("detecting")

# --- Roam (local wander, no pathfinding) ---

func _roam_step() -> void:
	if get_state() != "roam" or not game_state or not game_state.characters.has(char_id):
		return
	var cur := game_state.get_position(char_id)
	var target := _pick_roam_target(cur)
	game_state.command_move_to_pos(char_id, target)  # straight line — never A*
	_roam_seq += 1
	var scheduler := _get_scheduler()
	if scheduler:
		scheduler.schedule_after(roam_interval, _roam_step, _state_tag)

## Choose the next hop: rotate the heading by a deterministic wander angle, pull back toward the
## anchor near the circle's edge, clamp inside the radius, and bounce off a blocked grid cell. Pure
## function of the hop counter + enemy id (no wall-clock / randf), so 1x and 10x roam identically.
func _pick_roam_target(cur: Vector3) -> Vector3:
	var turn := (_roam_noise(0) - 0.5) * deg_to_rad(120.0)  # +/-60 deg of wander
	_roam_heading = _roam_heading.rotated(Vector3.UP, turn).normalized()
	var from_anchor := cur - _roam_anchor
	from_anchor.y = 0.0
	if from_anchor.length() > _roam_radius * 0.8:
		# Near the edge — steer back inward so the wander stays in its yard.
		_roam_heading = (_roam_heading + (-from_anchor).normalized() * 1.5).normalized()
	var target := cur + _roam_heading * roam_step_distance
	target.y = cur.y
	var off := target - _roam_anchor
	off.y = 0.0
	if off.length() > _roam_radius:
		target = _roam_anchor + off.normalized() * _roam_radius
		target.y = cur.y
	if game_state and game_state.grid:
		var lvl := game_state.get_character_level(char_id)
		var cell := game_state.grid.world_to_grid(target)
		if not game_state.grid.is_walkable(cell.x, cell.y, {}, {}, lvl):
			_roam_heading = -_roam_heading  # bounce off the wall; hold this hop
			return cur
	return target

## Deterministic pseudo-random in [0,1): a hash of the enemy id, the hop counter, and a salt. Free of
## the wall clock and randf, so the wander is identical under fast-forward and reproducible per run.
func _roam_noise(salt: int) -> float:
	return float(absi(hash("%s:%d:%d" % [char_id, _roam_seq, salt])) % 100000) / 100000.0

# --- Patrol ---

func _patrol_next_waypoint() -> void:
	if _patrol_waypoints.is_empty() or get_state() != "patrol":
		return
	var waypoint := _patrol_waypoints[_patrol_index]
	if game_state and game_state.characters.has(char_id):
		if game_state.grid:
			game_state.command_move_to_cell(char_id, game_state.grid.world_to_grid(waypoint))
		else:
			game_state.command_move_to_pos(char_id, waypoint)
	_patrol_index = (_patrol_index + 1) % _patrol_waypoints.size()
	var dist := global_position.distance_to(waypoint)
	var travel_time := dist / maxf(move_speed, 0.1) + 0.5
	var scheduler := _get_scheduler()
	if scheduler:
		scheduler.schedule_after(travel_time, _patrol_next_waypoint, _state_tag)

# --- Visual ---

## Override in subclasses for different mesh types. The body stays a CapsuleMesh (the elevator
## predators + chain enemy resize `_mesh.mesh as CapsuleMesh`), but it's crouched forward and dressed
## with dorsal spikes + a jutting head so it reads as a predator, not an idle sphere.
func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.24
	capsule.height = 0.78
	_mesh.mesh = capsule
	var body_color := color.darkened(0.25)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color
	mat.roughness = 0.85
	mat.metallic = 0.15
	_mesh.material_override = mat
	# Crouched, leaning forward (predatory stance) rather than standing upright.
	_mesh.position.y = 0.42
	_mesh.rotation = Vector3(deg_to_rad(78.0), 0.0, 0.0)
	add_child(_mesh)
	_build_creature_features(body_color)
	_eye_left = _make_eye(Vector3(-0.11, 0.5, 0.34))
	_eye_right = _make_eye(Vector3(0.11, 0.5, 0.34))

## Dorsal spikes + a forward head wedge — silhouette cues that read as a threat at gameplay distance.
func _build_creature_features(body_color: Color) -> void:
	var spike_mat := StandardMaterial3D.new()
	spike_mat.albedo_color = body_color.darkened(0.2)
	spike_mat.roughness = 0.7
	# A short ridge of back spikes.
	for i in range(3):
		var spike := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.075
		cone.height = 0.26 - i * 0.04
		spike.mesh = cone
		spike.material_override = spike_mat
		spike.position = Vector3(0.0, 0.62 - i * 0.02, -0.16 + i * 0.16)
		spike.rotation = Vector3(deg_to_rad(-28.0), 0.0, 0.0)
		add_child(spike)
	# A blunt head jutting forward over the eyes.
	var head := MeshInstance3D.new()
	var head_mesh := CylinderMesh.new()
	head_mesh.top_radius = 0.02
	head_mesh.bottom_radius = 0.17
	head_mesh.height = 0.34
	head.mesh = head_mesh
	head.material_override = spike_mat
	head.position = Vector3(0.0, 0.5, 0.28)
	head.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	add_child(head)

func _make_eye(pos: Vector3) -> OmniLight3D:
	var eye := OmniLight3D.new()
	eye.position = pos
	eye.light_color = Color(0.95, 0.1, 0.05)
	eye.light_energy = 0.4
	eye.omni_range = 0.8
	add_child(eye)
	return eye

func _set_eye_energy(energy: float) -> void:
	if _eye_left:
		_eye_left.light_energy = energy
	if _eye_right:
		_eye_right.light_energy = energy

func _set_mesh_color(c: Color) -> void:
	if _mesh and _mesh.material_override:
		(_mesh.material_override as StandardMaterial3D).albedo_color = c

func _fade_out(duration: float) -> void:
	if _mesh:
		var tween := create_tween()
		tween.tween_property(_mesh, "transparency", 1.0, duration)
	_set_eye_energy(0.0)

# --- Movement / Charge collision ---

func _process(delta: float) -> void:
	# GameState-driven position sync
	if game_state and char_id != "" and game_state.is_moving(char_id):
		var pos := game_state.get_position(char_id)
		global_position = Vector3(pos.x, global_position.y, pos.z)

	# Charge: a PURELY COSMETIC lunge. The hit itself is predicted — _land_attack is scheduled for the
	# contact tick in _enter_state("charge") and always connects (unless the target dodges), so the
	# strike never whiffs because of a frame-rate or fast-forward sampling miss. This just animates the
	# body toward the locked target position as a pure function of the scheduler tick.
	if _charging and get_state() == "charge":
		var scheduler := _get_scheduler()
		if scheduler and scheduler.is_paused():
			return
		var to_target := _charge_target_pos - _charge_start_pos
		to_target.y = 0
		var total_dist := to_target.length()
		var now_tick := scheduler.get_current_tick() if scheduler else _charge_start_tick
		var traveled := charge_speed * (now_tick - _charge_start_tick)
		var dir := to_target.normalized() if total_dist > 0.001 else Vector3.ZERO
		global_position = Vector3(
			_charge_start_pos.x + dir.x * minf(traveled, total_dist),
			global_position.y,
			_charge_start_pos.z + dir.z * minf(traveled, total_dist))

func _stop_movement() -> void:
	if game_state and game_state.characters.has(char_id):
		game_state.command_stop(char_id)

# --- Utilities ---

func _get_scheduler() -> EventScheduler:
	if game_state and game_state.scheduler:
		return game_state.scheduler
	return null

## Scheduler-authoritative world position of a target: GameState when the target is
## registered (so the charge clock and the target clock are the same), else the node.
func _charge_target_world(target_id: String) -> Vector3:
	if game_state and game_state.characters.has(target_id):
		return game_state.get_position(target_id)
	var node := _find_character_node(target_id)
	return (node as Node3D).global_position if node else Vector3.INF

func _find_character_node(target_id: String) -> Node:
	# Search parent first (Characters node), then siblings of parent (chunk nodes)
	for search_root in _get_search_roots():
		for child in search_root.get_children():
			if child == self:
				continue
			if child.has_method("get") and child.get("char_id") == target_id:
				return child
			if child.name.to_lower() == target_id:
				return child
	return null

func _get_search_roots() -> Array[Node]:
	var roots: Array[Node] = []
	var parent := get_parent()
	if parent:
		roots.append(parent)
		# Also search sibling containers (e.g. Characters node when enemy is in a chunk)
		if parent.get_parent():
			for sibling in parent.get_parent().get_children():
				if sibling != parent and sibling is Node3D:
					roots.append(sibling)
	return roots
