class_name Enemy
extends Node3D

## Base enemy with scheduler-driven state machine, HP, and detection.
## All state transitions and detection scans run through EventScheduler,
## so they respect speed multiplier (fast-forward) and pause automatically.
##
## Interfaces:
##   State Machine — idle, patrol, alert, pursuit, windup, charge, recover, dead
##   HP / Death    — take_damage(), die(), is_alive()
##   Detection     — periodic scan, white "!" on spotted character
##
## Attack cycle: pursuit → windup (pause, turn red) → charge (dash to locked
## position) → hit or miss → recover (still, blue→normal fade) → pursuit
##
## Extend and override _build_visual() for different enemy types.

# --- Configuration ---
@export var display_name := "Entity"
@export var color := Color(0.4, 0.15, 0.1)
@export var max_hp := 50.0
@export var move_speed := 1.5
@export var detection_range := 6.0
@export var scan_interval := 0.5
@export var pursuit_update_interval := 0.8

# Attack cycle config
@export var attack_range := 3.0
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

# --- State machine ---
var _state := "idle"
var _state_tag := ""
var _hp: float

# --- Detection ---
var _detection_targets: Array[String] = []
var _current_target_id := ""
var _alert_label: Label3D

# --- Patrol ---
var _patrol_waypoints: Array[Vector3] = []
var _patrol_index := 0

# --- Attack cycle ---
var _charge_target_pos := Vector3.ZERO
var _charging := false
var _charge_hit := false

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

# --- Public API ---

## Start the state machine. Call after game_state and char_id are set.
func activate() -> void:
	if _state == "dead":
		return
	if game_state and not game_state.detection_predicted.is_connected(_on_detection_predicted):
		game_state.detection_predicted.connect(_on_detection_predicted)
	_change_state("idle")

## Set patrol waypoints and switch to patrol state.
func set_patrol(waypoints: Array[Vector3]) -> void:
	_patrol_waypoints = waypoints
	_patrol_index = 0
	if _state != "dead":
		_change_state("patrol")

## Deal damage to this enemy.
func take_damage(amount: float) -> void:
	if _state == "dead":
		return
	_hp = maxf(0.0, _hp - amount)
	damaged.emit(amount, _hp)
	if _hp <= 0:
		die()

## Kill this enemy.
func die() -> void:
	_change_state("dead")

func is_alive() -> bool:
	return _hp > 0

func get_state() -> String:
	return _state

# --- State Machine Core ---

func _change_state(new_state: String) -> void:
	if new_state == _state and new_state != "idle":
		return
	var scheduler := _get_scheduler()
	if scheduler:
		scheduler.cancel_tag(_state_tag)
	_exit_state(_state)
	_state = new_state
	_enter_state(new_state)

func _enter_state(state: String) -> void:
	match state:
		"idle":
			pass  # Detection via GameState prediction signal
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
			# After pursuit_rescan_delay, drop back to detecting for new targets
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
			# Timeout: if we don't hit anything, recover anyway
			var scheduler := _get_scheduler()
			if scheduler:
				scheduler.schedule_after(charge_max_duration, _end_charge, _state_tag)
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
	# Only respond to detections when in a scanning state
	if _state not in ["idle", "patrol", "detecting"]:
		return
	_current_target_id = target_id
	target_spotted.emit(target_id)
	_change_state("alert")

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

# --- Pursuit → Windup → Charge → Recover cycle ---

func _begin_pursuit() -> void:
	if _state != "alert":
		return
	_remove_alert_label()
	_change_state("pursuit")

func _pursue_target() -> void:
	if _state != "pursuit" or _current_target_id == "" or not game_state:
		return
	var target_pos := game_state.get_position(_current_target_id)
	var dist := global_position.distance_to(target_pos)
	# Close enough to attack — wind up
	if dist < attack_range:
		_change_state("windup")
		return
	# Otherwise keep chasing
	if game_state.characters.has(char_id):
		game_state.command_move_to_pos(char_id, target_pos)
	var scheduler := _get_scheduler()
	if scheduler:
		scheduler.schedule_after(pursuit_update_interval, _pursue_target, _state_tag)

func _begin_charge() -> void:
	if _state != "windup":
		return
	_change_state("charge")

func _end_charge() -> void:
	if _state != "charge":
		return
	_change_state("recover")

func _resume_pursuit() -> void:
	if _state != "recover":
		return
	_set_mesh_color(_base_color)
	_change_state("pursuit")

func _begin_rescan() -> void:
	if _state != "pursuit":
		return
	_stop_movement()
	_change_state("detecting")

# --- Patrol ---

func _patrol_next_waypoint() -> void:
	if _patrol_waypoints.is_empty() or _state != "patrol":
		return
	var waypoint := _patrol_waypoints[_patrol_index]
	if game_state and game_state.characters.has(char_id):
		game_state.command_move_to_pos(char_id, waypoint)
	_patrol_index = (_patrol_index + 1) % _patrol_waypoints.size()
	var dist := global_position.distance_to(waypoint)
	var travel_time := dist / maxf(move_speed, 0.1) + 0.5
	var scheduler := _get_scheduler()
	if scheduler:
		scheduler.schedule_after(travel_time, _patrol_next_waypoint, _state_tag)

# --- Visual ---

## Override in subclasses for different mesh types.
func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.22
	capsule.height = 0.9
	_mesh.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	_mesh.material_override = mat
	_mesh.position.y = 0.45
	add_child(_mesh)
	# Red eyes
	_eye_left = _make_eye(Vector3(-0.1, 0.65, 0.15))
	_eye_right = _make_eye(Vector3(0.1, 0.65, 0.15))

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

	# Charge: move toward locked target position, check for collision
	# Speed scaled by scheduler speed multiplier so charge respects fast-forward
	if _charging and _state == "charge":
		var dir := (_charge_target_pos - global_position)
		dir.y = 0
		if dir.length() < 0.3:
			_end_charge()
			return
		var spd_mult := 1.0
		var scheduler := _get_scheduler()
		if scheduler:
			spd_mult = scheduler.get_speed()
		if scheduler and scheduler.is_paused():
			return
		global_position += dir.normalized() * charge_speed * delta * spd_mult
		if not _charge_hit:
			for target_id in _detection_targets:
				var target_node := _find_character_node(target_id)
				if not target_node:
					continue
				if global_position.distance_to(target_node.global_position) < 0.8:
					_charge_hit = true
					hit_target.emit(target_id, charge_damage)
					_end_charge()
					return

func _stop_movement() -> void:
	if game_state and game_state.characters.has(char_id):
		game_state.command_stop(char_id)

# --- Utilities ---

func _get_scheduler() -> EventScheduler:
	if game_state and game_state.scheduler:
		return game_state.scheduler
	return null

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
