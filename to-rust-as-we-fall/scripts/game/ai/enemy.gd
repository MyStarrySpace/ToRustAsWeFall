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
@export var alert_duration := 0.6      # spotting beat before the chase begins
@export var windup_duration := 0.8     # telegraph before the lunge
@export var charge_speed := 8.0
@export var charge_damage := 25.0
@export var charge_max_duration := 1.5
@export var lunge_gap := 0.6           # stop the lunge this far short of the target (no body-stacking)
@export var impact_duration := 0.14    # hitstop at the moment of connection
@export var recover_duration := 1.2    # cooldown after a strike (vulnerable window)
@export var stagger_duration := 0.5    # interrupt when the enemy itself is struck mid-aggro
@export var search_duration := 3.0     # how long to hunt at the last-known spot before giving up
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
var _last_known_target_pos := Vector3.ZERO

# --- Ambient "home" the enemy returns to after losing a target ("idle" | "roam" | "patrol") ---
var _home_mode := "idle"

# --- Patrol (authored routes) ---
var _patrol_waypoints: Array[Vector3] = []
var _patrol_index := 0

# --- Roam (undirected wander: cheap local hops, NEVER pathfinding) ---
var _roam_anchor := Vector3.ZERO
var _roam_radius := 0.0
var _roam_heading := Vector3(0.0, 0.0, -1.0)  # current wander direction
var _roam_seq := 0                            # deterministic hop counter (fast-forward invariant)

# --- Attack cycle ---
# The lunge is a REAL data-layer move at charge_speed (logged → replay-safe, visual follows via the
# _process sync), so the strike never teleports. _charging / _charge_hit / _charge_target_pos are the
# contract ChainEnemy reads (its segments deal contact damage during the same charge window).
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
	_build_fsm()

# --- Public API ---

## Start after game_state and char_id are set.
func activate() -> void:
	if get_state() == "dead":
		return
	# The FSM was built in _ready, possibly before game_state (chunks assign it after add_child). Now
	# that the scheduler exists, point the FSM at it so timed transitions / per-state schedules fire.
	if _fsm != null:
		_fsm.set_scheduler(_get_scheduler())
	if game_state and not game_state.detection_predicted.is_connected(_on_detection_predicted):
		game_state.detection_predicted.connect(_on_detection_predicted)
	_fsm.transition_to("idle")

## Set patrol waypoints (an AUTHORED route — pathfinds between waypoints to route around walls).
func set_patrol(waypoints: Array[Vector3]) -> void:
	_patrol_waypoints = waypoints
	_patrol_index = 0
	_home_mode = "patrol"
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
	_home_mode = "roam"
	if get_state() != "dead":
		_fsm.transition_to("roam")

## Apply damage. A hit taken mid-aggro staggers the enemy (a brief interrupt → counterplay), so the
## player can break a windup/charge by striking first.
func take_damage(amount: float) -> void:
	if get_state() == "dead":
		return
	_hp = maxf(0.0, _hp - amount)
	damaged.emit(amount, _hp)
	if _hp <= 0:
		die()
		return
	if get_state() in ["alert", "pursuit", "windup", "charge", "impact", "recover"]:
		_fsm.transition_to("stagger")

## Kill immediately.
func die() -> void:
	_fsm.transition_to("dead")

func is_alive() -> bool:
	return _hp > 0

func get_state() -> String:
	return _fsm.current() if _fsm != null else ""

# --- State Machine Core (reusable StateMachine: tag-scoped scheduling + exit/enter hooks) ---

const ENEMY_STATES := ["idle", "roam", "patrol", "alert", "pursuit", "windup", "charge", "impact", "recover", "stagger", "search", "return", "dead"]

# Telegraph colours (the body reads its intent at a glance).
const WINDUP_COLOR := Color(0.9, 0.15, 0.1)    # red — about to strike
const IMPACT_COLOR := Color(1.0, 0.85, 0.5)    # flash on connection
const RECOVER_COLOR := Color(0.2, 0.3, 0.7)    # blue — vulnerable cooldown
const STAGGER_COLOR := Color(0.85, 0.7, 0.2)   # yellow — interrupted

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
			_set_eye_energy(0.4)
		"roam":
			_set_eye_energy(0.5)
			_roam_step()
		"patrol":
			_set_eye_energy(0.5)
			_patrol_next_waypoint()
		"alert":
			_show_alert_on_target()
			_set_eye_energy(1.6)
			_anim_pop(1.18)
			_fsm.schedule(alert_duration, _begin_pursuit)
		"pursuit":
			_set_eye_energy(2.0)
			_set_mesh_color(_base_color)
			_pursue_target()
			if pursuit_rescan_delay > 0:
				_fsm.schedule(pursuit_rescan_delay, _begin_search)
		"windup":
			_stop_movement()
			_set_mesh_color(WINDUP_COLOR)
			_set_eye_energy(3.0)
			_anim_squash()  # crouch/anticipation
			_fsm.schedule(windup_duration, _begin_charge)
		"charge":
			_begin_lunge()
		"impact":
			_apply_strike()
			_set_mesh_color(IMPACT_COLOR)
			_anim_punch()
			_fsm.schedule(impact_duration, _begin_recover)
		"recover":
			_charging = false
			_stop_movement()
			_set_mesh_color(RECOVER_COLOR)
			_set_eye_energy(0.8)
			_anim_settle()
			# Cosmetic fade blue -> base over the cooldown (never gates the transition).
			if _mesh and _mesh.material_override:
				var tween := create_tween()
				tween.tween_method(_set_mesh_color, RECOVER_COLOR, _base_color, recover_duration)
			_fsm.schedule(recover_duration, _after_recover)
		"stagger":
			_charging = false
			_stop_movement()
			_set_mesh_color(STAGGER_COLOR)
			_set_eye_energy(0.5)
			_anim_recoil()
			_fsm.schedule(stagger_duration, _after_stagger)
		"search":
			_set_eye_energy(1.0)
			_set_mesh_color(_base_color)
			_begin_search_move()
			_fsm.schedule(search_duration, _begin_return)
		"return":
			_set_eye_energy(0.5)
			_set_mesh_color(_base_color)
			_begin_return_move()
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
			# Restore the chase speed (the lunge ran at charge_speed through the data layer).
			if game_state != null and game_state.characters.has(char_id):
				game_state.change_move_speed(char_id, move_speed)

# --- Detection (via GameState predictive signal) ---

func _on_detection_predicted(detector_id: String, target_id: String) -> void:
	if detector_id != char_id:
		return
	if target_id not in _detection_targets:
		return
	# Only respond to detections when in a scanning state (roaming / searching / returning still see).
	if get_state() not in ["idle", "roam", "patrol", "search", "return"]:
		return
	# Never (re)acquire a downed target — that was the "alert -> chase a corpse forever" loop.
	if game_state.characters.has(target_id):
		var t_stats: Dictionary = game_state.characters[target_id].stats
		if t_stats.has("hp") and float(t_stats["hp"]) <= 0.0:
			return
	_current_target_id = target_id
	if game_state:
		_last_known_target_pos = game_state.get_position(target_id)
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

# --- Attack cycle: alert -> pursuit -> windup -> charge -> impact -> recover (-> pursuit / search) ---
# Lose the target (rescan timeout, or it goes down) -> search the last-known spot -> return home.

func _begin_pursuit() -> void:
	if get_state() != "alert":
		return
	_remove_alert_label()
	_fsm.transition_to("pursuit")

func _pursue_target() -> void:
	if get_state() != "pursuit":
		return
	if not _target_engageable():
		_fsm.transition_to("search")
		return
	var target_pos := game_state.get_position(_current_target_id)
	_last_known_target_pos = target_pos
	var dist := _planar_dist(_self_pos(), target_pos)
	# Close enough to wind up.
	if dist <= attack_range:
		_fsm.transition_to("windup")
		return
	# Otherwise keep chasing (pursuit is the ONLY state that pathfinds).
	if game_state.characters.has(char_id):
		if game_state.grid:
			game_state.command_move_to_cell(char_id, game_state.grid.world_to_grid(target_pos))
		else:
			game_state.command_move_to_pos(char_id, target_pos)
	_fsm.schedule(pursuit_update_interval, _pursue_target)

func _begin_charge() -> void:
	if get_state() != "windup":
		return
	_fsm.transition_to("charge")

## Commit the lunge: a fast data-layer move (logged → replay-safe, visual follows via the _process
## sync) toward a point just short of the target, locked NOW (freshest). The strike is scheduled for
## the contact tick — it lands for sure unless the target dodges in the window. Because the body
## actually MOVES through the data layer, there is no teleport-snap at impact.
func _begin_lunge() -> void:
	_charging = true
	_charge_hit = false
	if not _target_engageable() or not game_state.characters.has(char_id):
		_fsm.transition_to("recover")
		return
	var ep := _self_pos()
	var tp := game_state.get_position(_current_target_id)
	_charge_target_pos = tp
	var flat := Vector3(tp.x - ep.x, 0.0, tp.z - ep.z)
	var dist := flat.length()
	var dir := flat.normalized() if dist > 0.001 else Vector3.ZERO
	var lunge_to := tp - dir * lunge_gap
	var lunge_dist := maxf(0.0, dist - lunge_gap)
	game_state.change_move_speed(char_id, charge_speed)
	if lunge_dist > 0.05:
		game_state.command_move_to_pos(char_id, lunge_to)
	var contact: float = minf(lunge_dist / maxf(charge_speed, 0.1), charge_max_duration)
	_fsm.schedule(contact, _end_charge)

## Resolve the charge into the impact beat. Called by the scheduled contact (standard enemy) AND by
## ChainEnemy when one of its trailing segments touches the target early — both route through the same
## impact, deduped by _charge_hit so the strike resolves exactly once.
func _end_charge() -> void:
	if get_state() != "charge":
		return
	_fsm.transition_to("impact")

## Resolve a single charge strike against `tid`, exactly once per charge (deduped by _charge_hit). This is
## the SHARED path for the standard scheduled impact AND a ChainEnemy segment contact, so both honour the
## dodge window, never hit a downed target, and apply REAL data-layer damage (adjust_stat) — not just a
## cosmetic signal. Returns true if the strike landed.
func _resolve_strike(tid: String) -> bool:
	if _charge_hit:
		return false  # already resolved this charge
	if tid == "" or game_state == null or not game_state.characters.has(tid):
		return false
	# Never strike a target that is already down (e.g. another enemy felled it mid-charge).
	if float(game_state.characters[tid].stats.get("hp", 1.0)) <= 0.0:
		return false
	# Dodge window: a target that can roll (dodge_unlocked) and auto-evades slips the committed strike.
	if game_state.has_method("dodge_roll"):
		var st: Dictionary = game_state.characters[tid].stats
		if bool(st.get("dodge_unlocked", false)) and bool(st.get("auto_dodge", false)) and not game_state.is_dodging(tid):
			game_state.dodge_roll(tid, _perp_to_target(tid))
	if game_state.has_method("is_dodging") and game_state.is_dodging(tid):
		return false
	_charge_hit = true
	if game_state.has_method("adjust_stat"):
		game_state.adjust_stat(tid, "hp", -charge_damage)
	_flash_target(tid)
	hit_target.emit(tid, charge_damage)
	return true

## The strike resolves at impact (standard enemy). ChainEnemy routes its segment contact through the same
## _resolve_strike so the two paths can't diverge.
func _apply_strike() -> void:
	_resolve_strike(_current_target_id)

func _begin_recover() -> void:
	if get_state() != "impact":
		return
	_fsm.transition_to("recover")

## After the cooldown, re-evaluate: strike again if the target is in range, chase if it fled, else
## hunt the last-known spot. Never loop on a downed target (that was the "attacks a corpse" bug).
func _after_recover() -> void:
	if get_state() != "recover":
		return
	if not _target_engageable():
		_fsm.transition_to("search")
		return
	var dist := _planar_dist(_self_pos(), game_state.get_position(_current_target_id))
	_fsm.transition_to("windup" if dist <= attack_range else "pursuit")

func _after_stagger() -> void:
	if get_state() != "stagger":
		return
	_fsm.transition_to("pursuit" if _target_engageable() else "search")

func _begin_search() -> void:
	if get_state() != "pursuit":
		return
	_fsm.transition_to("search")

func _begin_search_move() -> void:
	# Walk to where the target was last seen and look around; detection stays live while searching.
	if game_state and game_state.characters.has(char_id):
		game_state.command_move_to_pos(char_id, _last_known_target_pos)

func _begin_return() -> void:
	if get_state() != "search":
		return
	_fsm.transition_to("return")

func _begin_return_move() -> void:
	# Head home, then resume the ambient mode the enemy was in before it gave chase.
	var dest := _self_pos()
	if _home_mode == "roam":
		dest = _roam_anchor
		if game_state and game_state.characters.has(char_id):
			game_state.command_move_to_pos(char_id, dest)
	var travel := _planar_dist(_self_pos(), dest) / maxf(move_speed, 0.1) + 0.1
	_fsm.schedule(travel, _resume_home)

func _resume_home() -> void:
	if get_state() != "return":
		return
	match _home_mode:
		"roam":
			_fsm.transition_to("roam")
		"patrol":
			_fsm.transition_to("patrol")
		_:
			_fsm.transition_to("idle")

## True while the current target exists and is not downed (hp stat present and <= 0 means down).
func _target_engageable() -> bool:
	if _current_target_id == "" or game_state == null:
		return false
	if not game_state.characters.has(_current_target_id):
		return false
	var stats: Dictionary = game_state.characters[_current_target_id].stats
	if stats.has("hp") and float(stats["hp"]) <= 0.0:
		return false
	return true

## Scheduler-authoritative self position (data layer when registered, else the node).
func _self_pos() -> Vector3:
	if game_state and game_state.characters.has(char_id):
		return game_state.get_position(char_id)
	return global_position

func _planar_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

## A sideways direction relative to the line from the target to this enemy (the dodge slip axis).
func _perp_to_target(target_id: String) -> Vector3:
	var ap := _self_pos()
	var tp := game_state.get_position(target_id)
	var approach := Vector3(ap.x - tp.x, 0.0, ap.z - tp.z)
	var perp := Vector3(-approach.z, 0.0, approach.x)
	return perp.normalized() if perp.length_squared() > 0.001 else Vector3(1.0, 0.0, 0.0)

## Brief flinch on a struck character — a universal scale-punch on its node (cosmetic; any Node3D).
func _flash_target(target_id: String) -> void:
	var node := _find_character_node(target_id) as Node3D
	if node == null:
		return
	var base: Vector3 = node.scale
	var tween := create_tween()
	tween.tween_property(node, "scale", base * 1.25, 0.07)
	tween.tween_property(node, "scale", base, 0.18)

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

# --- Attack-beat animation (cosmetic scale pulses; never gate a transition on these) ---
# Each beat reshapes the body so the player reads intent: a squash anticipation before the lunge, a
# punch on impact, a flinch on stagger. ChainEnemy has no _mesh (it overrides _build_visual), so these
# safely no-op for it — its segments carry their own motion.
var _anim_tween: Tween

func _play_scale(keys: Array) -> void:
	if _mesh == null:
		return
	if _anim_tween != null and _anim_tween.is_valid():
		_anim_tween.kill()
	_anim_tween = create_tween()
	for k in keys:
		_anim_tween.tween_property(_mesh, "scale", k[0], float(k[1]))

func _anim_pop(peak := 1.18) -> void:      # alert: quick spot-tell
	_play_scale([[Vector3.ONE * peak, 0.08], [Vector3.ONE, 0.12]])

func _anim_squash() -> void:               # windup: crouch/anticipation
	_play_scale([[Vector3(1.2, 0.8, 1.2), 0.12]])

func _anim_punch() -> void:                # impact: sharp connect
	_play_scale([[Vector3.ONE * 1.3, 0.05], [Vector3.ONE, 0.12]])

func _anim_settle() -> void:               # recover: ease back to rest
	_play_scale([[Vector3.ONE, 0.2]])

func _anim_recoil() -> void:               # stagger: flinch inward
	_play_scale([[Vector3.ONE * 0.78, 0.06], [Vector3.ONE, 0.18]])

# --- Movement / Charge collision ---

func _process(_delta: float) -> void:
	# The body is a pure mirror of the data layer — including the charge, which is now a real
	# data-layer move at charge_speed (so the lunge is smooth and never teleport-snaps at impact).
	if game_state and char_id != "" and game_state.is_moving(char_id):
		var pos := game_state.get_position(char_id)
		global_position = Vector3(pos.x, global_position.y, pos.z)

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
