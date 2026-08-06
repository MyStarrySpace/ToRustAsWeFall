@tool
extends "res://scripts/tutorial/tutorial_sequence.gd"

## Functional showcase scene. Every station uses the live systems that the
## real levels already rely on: enemy AI, flure redirection, iron hazard
## damage, the hide/run encounter logic, pushable objects, throw physics,
## and pendulum prediction.

const GRID_SIZE := Vector2i(84, 44)
const GRID_ORIGIN := Vector3(-18.0, 0.0, -12.0)

const FLOOR_COLOR := Color(0.055, 0.055, 0.065)
const WALL_COLOR := Color(0.12, 0.12, 0.14)
const STATION_FLOOR_COLOR := Color(0.075, 0.08, 0.095)
const STATION_EDGE_COLOR := Color(0.17, 0.18, 0.2)

const DEFAULT_HP := 100.0
const DAMAGE_IFRAME := 0.8
const IRON_DAMAGE_PER_SEC := 8.0
const IRON_DAMAGE_INTERVAL := 0.25
const PENDULUM_MIN_DAMAGE := 10.0
const PHYSICS_MIN_DAMAGE := 8.0

const DAMAGE_AUTHORITY_VERSION := 1
const DAMAGE_AUTHORITY_KEY := "runtime:showcase_room:damage"
const DAMAGE_PHASE_ACTIVE := "active"
const DAMAGE_PHASE_RESOLVING := "resolving"
const IRON_DAMAGE_TAG := "showcase_iron_damage"
const DAMAGE_RESOLVE_TAG := "showcase_damage_resolve"

const SHOWCASE_FLURE_DURATION := 8.0
const HIDE_LURE_DURATION := 6.0
const HIDE_SWARM_SPEED := 8.0
const HIDE_SWARM_DETECT_RADIUS := 1.7
const HIDE_SWARM_OFFSETS := [-1.8, -0.6, 0.6, 1.8]

const SPAWN_RECT := Rect2i(1, 17, 9, 11)
const ENEMY_RECT := Rect2i(11, 6, 13, 10)
const CHAIN_RECT := Rect2i(11, 28, 13, 10)
const IRON_RECT := Rect2i(26, 6, 16, 10)
const PHYSICS_RECT := Rect2i(26, 28, 18, 10)
const FLURE_RECT := Rect2i(44, 14, 15, 14)
const HIDE_RECT := Rect2i(60, 14, 18, 14)

const START_CELLS := {
	"aster": Vector2i(5, 22),
	"peris": Vector2i(3, 24),
	"endo": Vector2i(3, 20),
}

const CHARACTER_DISPLAY_NAMES := {
	"aster": "Aster",
	"peris": "Peris",
	"endo": "Endo",
}

const CHARACTER_COLORS := {
	"aster": Color(0.29, 0.62, 1.0),
	"peris": Color(1.0, 0.67, 0.27),
	"endo": Color(0.4, 0.72, 0.55),
}

const CHARACTER_SPEEDS := {
	"aster": 3.4,
	"peris": 3.4,
	"endo": 2.6,
}

const FOLLOW_OFFSETS := {
	"aster": Vector3(-1.6, 0.0, 0.9),
	"peris": Vector3(-1.6, 0.0, 1.6),
	"endo": Vector3(-1.6, 0.0, -0.9),
}

const ENEMY_PATROL_A := Vector2i(15, 11)
const ENEMY_PATROL_B := Vector2i(21, 11)
const ENEMY_PROBE_CELL := Vector2i(16, 11)

const CHAIN_HEAD_CELL := Vector2i(18, 33)
const CHAIN_PATROL_A := Vector2i(17, 33)
const CHAIN_PATROL_B := Vector2i(20, 33)
const CHAIN_PROBE_CELL := Vector2i(18, 33)

const IRON_PATCH_RECTS := [
	Rect2i(29, 9, 5, 4),
	Rect2i(35, 10, 4, 4),
]

const IRON_PROBE_CELL := Vector2i(31, 10)
const IRON_SAFE_CELL := Vector2i(28, 10)

const PUSH_BARREL_CELL := Vector2i(31, 33)
const LAUNCHER_BARREL_CELL := Vector2i(38, 31)
const LAUNCHER_INTERACT_CELL := Vector2i(36, 29)
const PHYSICS_THROW_START := Vector3(20.5, 1.2, 17.5)
const PHYSICS_THROW_VELOCITY := Vector3(7.5, 5.2, 0.0)

const PENDULUM_ID := "showcase_pendulum"
const PENDULUM_ANCHOR := Vector3(15.5, 6.2, 19.5)
const PENDULUM_LENGTH := 4.6
const PENDULUM_PROBE := Vector3(13.4, 0.0, 19.5)

const SHOWCASE_FLURE_CELL := Vector2i(48, 24)
const FLURE_ENEMY_CELLS := [
	Vector2i(53, 21),
	Vector2i(55, 22),
	Vector2i(53, 24),
]
const FLURE_PROBE_CELL := Vector2i(55, 22)

const HIDE_ENTRY_CELL := Vector2i(61, 20)
const HIDE_LURE_CELL := Vector2i(64, 20)
const HIDE_SPOT_CELL := Vector2i(69, 26)
const HIDE_SHELTER_CELL := Vector2i(76, 20)
const HIDE_EXPOSED_WAIT_CELL := Vector2i(59, 20)
const HIDE_SWARM_CLUSTER_X := 58.5

var _grid: GridWorld

var _hud
var _info_label: Label
var _characters_root: Node3D
var _hazards_root: Node3D

var _characters: Dictionary = {}
var _active_char_id := ""
var _perception_cycle := 0
var _run_active := false

var _interactables: Array = []
var _iron_patches: Array[Dictionary] = []

var _standard_enemy: Enemy
var _chain_enemy: ChainEnemy
var _enemy_nodes: Array[Enemy] = []
var _flure_enemies: Array[Enemy] = []

var _showcase_flure_mesh: MeshInstance3D
var _showcase_flure_light: OmniLight3D
var _showcase_flure_interactable
var _showcase_flure_active := false

var _hide_run_lure_mesh: MeshInstance3D
var _hide_run_lure_light: OmniLight3D
var _hide_run_lure_interactable
var _hide_swarm_units: Array[Dictionary] = []
var _hide_phase := "ready"
var _hide_party_hidden := false
var _hide_lure_expire_tick := -1.0
var _hide_last_outcome := ""

var _physics_visuals: Dictionary = {}
var _physics_defaults: Dictionary = {}
var _pendulum_visuals: Dictionary = {}

var _physics_event_log: Array[Dictionary] = []
var _pendulum_event_log: Array[Dictionary] = []
var _enemy_hit_log: Array[Dictionary] = []

func _build_scene() -> void:
	_init_grid()
	_build_environment()
	_build_spawn_station()
	_build_enemy_station()
	_build_chain_station()
	_build_iron_station()
	_build_physics_station()
	_build_flure_station()
	_build_hide_station()

func _build_characters() -> void:
	_characters_root = Node3D.new()
	_characters_root.name = "Characters"
	add_child(_characters_root)

	for char_id in ["aster", "peris", "endo"]:
		var node := _create_player_character(CHARACTER_DISPLAY_NAMES[char_id], CHARACTER_COLORS[char_id])
		node.name = CHARACTER_DISPLAY_NAMES[char_id]
		node.position = _cell_world(START_CELLS[char_id], 0.5)
		if not Engine.is_editor_hint():
			node.grid_world = _grid
		_characters_root.add_child(node)
		_characters[char_id] = node

	if not Engine.is_editor_hint():
		_setup_game_camera(_characters["aster"], Vector3(0, 18, 12))
		_camera.set_pan_enabled(true)

func _register_characters() -> void:
	_game_state.grid = _grid

	for char_id in _characters.keys():
		var node: CharacterBody3D = _characters[char_id]
		_register_gs_character(char_id, node, CHARACTER_SPEEDS[char_id], {
			"hp": GameState.HP_MAX,
			"stamina": GameState.STAMINA_MAX,
		})

	for enemy in _enemy_nodes:
		enemy.game_state = _game_state
		_register_gs_character(enemy.char_id, enemy, enemy.move_speed, {
			"detection_range": enemy.detection_range,
		})

	# Showcase starts every run from full stats so
	# nothing carries over between sessions.
	_game_state.reset_characters_to_full()

func _setup_ui() -> void:
	_hud = preload("res://scenes/ui/game_hud.tscn").instantiate()
	add_child(_hud)
	_hud.show_pause_toggle(false)
	_hud.show_run_toggle(false)
	_hud.pause_toggled.connect(func(paused: bool):
		if paused:
			_scheduler.pause()
		else:
			_scheduler.resume()
	)
	_hud.run_toggled.connect(_on_run_toggled)
	_hud.character_selection_changed.connect(_on_character_selected)

	for char_id in ["aster", "peris", "endo"]:
		_hud.add_portrait(char_id, CHARACTER_DISPLAY_NAMES[char_id], CHARACTER_COLORS[char_id])
		_hud.set_portrait_stat(char_id, "hp", DEFAULT_HP)
		_hud.set_portrait_stat(char_id, "sta", 100.0)
		_hud.set_portrait_stat(char_id, "atp", 6.0)

	var panel := preload("res://scenes/ui/showcase_info_overlay.tscn").instantiate() as CanvasLayer
	add_child(panel)
	_info_label = panel.get_node("InfoLabel") as Label

func _begin() -> void:
	_game_state.physics_collision.connect(_on_physics_collision)
	_game_state.pendulum_hit.connect(_on_pendulum_hit)
	_game_state.stat_changed.connect(_on_showcase_stat_changed)
	_game_state.character_downed.connect(_on_showcase_character_downed)
	_game_state.character_restored.connect(_on_showcase_character_restored)

	for enemy in _enemy_nodes:
		enemy.hit_target.connect(_on_enemy_hit)

	_setup_enemy_behaviors()
	_register_pendulum_visual(PENDULUM_ID, PENDULUM_ANCHOR)
	_reset_physics_station()
	_reset_hide_encounter()
	_set_showcase_flure_active(false)
	_start_damage_authority()
	_sync_all_character_stats()

	for interactable in _interactables:
		interactable.dialogue_box = _dialogue
		interactable.show_tutorial_label()

	_select_character("aster")
	_hud.show_message("Showcase ready. Walk each lane to verify the live systems.", 2.5)

func _get_speed_recipients() -> Array:
	return _interactables

func _compute_speed() -> float:
	if _scheduler.is_paused():
		return 0.0
	return 10.0 if Input.is_key_pressed(KEY_F) else 1.0

func _on_process(delta: float, spd: float) -> void:
	for interactable in _interactables:
		interactable.active_character = _active_char_id

	_update_followers()
	_update_pendulum_visuals()
	_update_hide_encounter(delta, spd)

func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		match key_event.keycode:
			KEY_SPACE:
				_toggle_pause()
			KEY_TAB:
				_cycle_character()
			KEY_P:
				_cycle_perception()
			KEY_Z:
				_toggle_run()
			KEY_R:
				get_tree().reload_current_scene()
			KEY_1:
				_select_character("aster")
			KEY_2:
				_select_character("peris")
			KEY_3:
				_select_character("endo")

func _toggle_pause() -> void:
	if _scheduler.is_paused():
		_scheduler.resume()
	else:
		_scheduler.pause()
	_hud.set_paused(_scheduler.is_paused())

func _toggle_run() -> void:
	_run_active = not _run_active
	_hud.set_run_mode(_run_active)
	_apply_active_run_state()

func _on_run_toggled(is_running: bool) -> void:
	_run_active = is_running
	_apply_active_run_state()

func _cycle_character() -> void:
	if _characters.is_empty():
		return
	var next_id: String = _hud.get_next_portrait_id(_active_char_id)
	_select_character(next_id)

func _select_character(char_id: String) -> void:
	if not _characters.has(char_id):
		return
	if _active_char_id == char_id:
		return

	if _active_char_id != "" and _characters.has(_active_char_id):
		var previous: CharacterBody3D = _characters[_active_char_id]
		previous.set_move_enabled(false)
		previous.set_running(false)
		if _game_state.characters.has(_active_char_id):
			_game_state.change_move_speed(_active_char_id, CHARACTER_SPEEDS[_active_char_id])

	_active_char_id = char_id
	_player = _characters[char_id]
	_player.set_move_enabled(not _game_state.is_downed(char_id))
	_player.set_running(_run_active)
	if _camera:
		_camera.target = _player
	_hud.set_active_portrait(char_id)
	_apply_active_run_state()

	for interactable in _interactables:
		interactable.active_character = _active_char_id

func _apply_active_run_state() -> void:
	if _active_char_id == "" or not _characters.has(_active_char_id):
		return
	var active_node: CharacterBody3D = _characters[_active_char_id]
	var base_speed: float = CHARACTER_SPEEDS[_active_char_id]
	active_node.set_running(_run_active)
	if _game_state.characters.has(_active_char_id):
		var move_speed: float = active_node.run_speed if _run_active else base_speed
		_game_state.change_move_speed(_active_char_id, move_speed)

func _on_character_selected(selected_ids: Array) -> void:
	if selected_ids.size() > 0:
		_select_character(selected_ids[0])

func _cycle_perception() -> void:
	_perception_cycle = (_perception_cycle + 1) % 3
	var target: Node3D = _characters.get(_active_char_id, null)
	match _perception_cycle:
		0:
			if _perception_quad:
				_perception_quad.visible = false
			_hud.show_message("Perception: OFF", 1.2)
		1:
			if target:
				_setup_perception("data", target)
			_hud.show_message("Perception: DATA", 1.2)
		2:
			if target:
				_setup_perception("fog", target)
			_hud.show_message("Perception: FOG", 1.2)

func _update_followers() -> void:
	if _active_char_id == "" or not _characters.has(_active_char_id):
		return
	var leader: CharacterBody3D = _characters[_active_char_id]
	for char_id in _characters.keys():
		if char_id == _active_char_id or _game_state.get_stat(char_id, "hp") <= 0.0:
			continue
		var follower: CharacterBody3D = _characters[char_id]
		if follower.global_position.distance_to(leader.global_position) > 2.8 and not _game_state.is_moving(char_id):
			_game_state.command_move_to_pos(char_id, leader.global_position + FOLLOW_OFFSETS[char_id])

## Showcase damage is still deliberately simple, but it now belongs to the same truthful
## simulation as the rest of the game. GameState owns HP/downed state. This versioned record owns
## the fixed iron cadence, discrete-impact i-frame deadlines, and any damage transaction caught
## between its commitment signal and its canonical stat write.
func _start_damage_authority() -> void:
	if _scheduler == null or _game_state == null:
		return
	var record := _damage_authority_record()
	if record.is_empty():
		record = {
			"version": DAMAGE_AUTHORITY_VERSION,
			"phase": DAMAGE_PHASE_ACTIVE,
			"next_iron_tick": float(_scheduler.get_current_tick()) + IRON_DAMAGE_INTERVAL,
			"iframe_deadlines": {},
			"transaction_serial": 0,
		}
		_game_state.set_world_state(DAMAGE_AUTHORITY_KEY, record)
	_attach_damage_authority(record)


func _damage_authority_record() -> Dictionary:
	if _game_state == null:
		return {}
	var value: Variant = _game_state.get_world_state(DAMAGE_AUTHORITY_KEY, null)
	if not value is Dictionary:
		return {}
	var record := (value as Dictionary).duplicate(true)
	if int(record.get("version", 0)) != DAMAGE_AUTHORITY_VERSION:
		return {}
	var phase := str(record.get("phase", ""))
	if phase not in [DAMAGE_PHASE_ACTIVE, DAMAGE_PHASE_RESOLVING]:
		return {}
	if not record.get("iframe_deadlines", {}) is Dictionary:
		return {}
	return record


func _attach_damage_authority(record: Dictionary) -> void:
	if _scheduler == null:
		return
	_scheduler.cancel_tag(IRON_DAMAGE_TAG)
	_scheduler.cancel_tag(DAMAGE_RESOLVE_TAG)
	if record.is_empty():
		return
	if str(record.get("phase", "")) == DAMAGE_PHASE_RESOLVING:
		# Restore performs no consequence. The already-committed transaction resumes on the
		# scheduler lane at the saved tick, so pause/fast-forward/replay retain one outcome.
		_scheduler.schedule_at(
			float(_scheduler.get_current_tick()),
			_resolve_pending_damage,
			DAMAGE_RESOLVE_TAG
		)
		return
	var deadline := float(record.get("next_iron_tick", -1.0))
	if deadline < 0.0:
		return
	_arm_iron_damage_tick(deadline)


func _arm_iron_damage_tick(deadline: float) -> void:
	if _scheduler == null:
		return
	_scheduler.cancel_tag(IRON_DAMAGE_TAG)
	var scheduled_tick := maxf(float(_scheduler.get_current_tick()), deadline)
	_scheduler.schedule_at(
		scheduled_tick,
		_on_iron_damage_tick.bind(deadline),
		IRON_DAMAGE_TAG
	)


func _on_iron_damage_tick(expected_deadline: float) -> void:
	var record := _damage_authority_record()
	if record.is_empty() or str(record.get("phase", "")) != DAMAGE_PHASE_ACTIVE:
		return
	if not is_equal_approx(float(record.get("next_iron_tick", -1.0)), expected_deadline):
		return
	var now := float(_scheduler.get_current_tick())
	record["next_iron_tick"] = maxf(now, expected_deadline) + IRON_DAMAGE_INTERVAL
	var results: Array[Dictionary] = []
	for char_id_v in _characters.keys():
		var char_id := str(char_id_v)
		if not _game_state.characters.has(char_id) \
				or _game_state.get_stat(char_id, "hp") <= 0.0:
			continue
		if not _position_is_in_iron(_game_state.get_position(char_id)):
			continue
		results.append(_make_damage_result(
			char_id,
			IRON_DAMAGE_PER_SEC * IRON_DAMAGE_INTERVAL,
			"iron bloom"
		))
	_commit_damage_results(record, results)


func _position_is_in_iron(position: Vector3) -> bool:
	for patch in _iron_patches:
		var patch_position: Vector3 = patch.pos
		var patch_size: Vector3 = patch.size
		if absf(position.x - patch_position.x) <= patch_size.x / 2.0 \
				and absf(position.z - patch_position.z) <= patch_size.z / 2.0:
			return true
	return false


func _apply_damage(char_id: String, amount: float, source: String, continuous := false) -> bool:
	if _game_state == null or _scheduler == null \
			or not _game_state.characters.has(char_id) or amount <= 0.0:
		return false
	var record := _damage_authority_record()
	if record.is_empty() or str(record.get("phase", "")) != DAMAGE_PHASE_ACTIVE:
		return false
	var hp_before := _game_state.get_stat(char_id, "hp")
	if hp_before <= 0.0:
		return false
	var now := float(_scheduler.get_current_tick())
	if not continuous:
		var iframe_deadlines := (record.get("iframe_deadlines", {}) as Dictionary).duplicate(true)
		if now < float(iframe_deadlines.get(char_id, -1.0)):
			return false
		iframe_deadlines[char_id] = now + DAMAGE_IFRAME
		record["iframe_deadlines"] = iframe_deadlines
	var applied := _commit_damage_results(record, [
		_make_damage_result(char_id, amount, source),
	])
	if applied and not continuous and _hud != null:
		_hud.show_message(
			"%s hit by %s" % [CHARACTER_DISPLAY_NAMES.get(char_id, char_id), source],
			1.2
		)
	return applied


func _make_damage_result(char_id: String, amount: float, source: String) -> Dictionary:
	var hp_before := _game_state.get_stat(char_id, "hp")
	return {
		"actor_id": char_id,
		"source": source,
		"amount": amount,
		"hp_before": hp_before,
		"hp_after": maxf(0.0, hp_before - amount),
	}


func _commit_damage_results(record: Dictionary, results: Array) -> bool:
	if _game_state == null or _scheduler == null \
			or str(record.get("phase", "")) != DAMAGE_PHASE_ACTIVE:
		return false
	if results.is_empty():
		# The cadence still advances authoritatively while nobody is exposed, but an empty beat
		# is not a damage transaction and needs no resolving phase.
		_game_state.set_world_state(DAMAGE_AUTHORITY_KEY, record)
		_attach_damage_authority(record)
		return false
	record["phase"] = DAMAGE_PHASE_RESOLVING
	record["committed_tick"] = float(_scheduler.get_current_tick())
	record["transaction_serial"] = int(record.get("transaction_serial", 0)) + 1
	record["damage_results"] = results.duplicate(true)
	# The transaction is authoritative before any stat signal can request a save. A save at this
	# seam resumes the exact absolute result instead of either granting immunity or double damage.
	_game_state.set_world_state(DAMAGE_AUTHORITY_KEY, record)
	_resolve_pending_damage()
	return not results.is_empty()


func _resolve_pending_damage() -> void:
	if _scheduler != null:
		_scheduler.cancel_tag(DAMAGE_RESOLVE_TAG)
	var record := _damage_authority_record()
	if record.is_empty() or str(record.get("phase", "")) != DAMAGE_PHASE_RESOLVING:
		return
	for result_v in record.get("damage_results", []):
		if not result_v is Dictionary:
			continue
		var result := result_v as Dictionary
		var char_id := str(result.get("actor_id", ""))
		if char_id == "" or not _game_state.characters.has(char_id):
			continue
		var target_hp := maxf(0.0, float(result.get("hp_after", 0.0)))
		var current_hp := _game_state.get_stat(char_id, "hp")
		var applied_now := false
		# A signal-time save may already contain this exact stat write. Never repeat it; if
		# another committed source made HP even lower, this transaction cannot heal it.
		if current_hp > target_hp + 0.0001:
			_game_state.set_stat(char_id, "hp", target_hp, str(result.get("source", "showcase")))
			applied_now = true
		if target_hp <= 0.0 and not _game_state.is_downed(char_id):
			_game_state.down_character(char_id)
		elif applied_now and _characters.has(char_id):
			_flash_character(_characters[char_id], Color(1.0, 0.6, 0.55, 0.6))
	record["phase"] = DAMAGE_PHASE_ACTIVE
	record.erase("committed_tick")
	record.erase("damage_results")
	_game_state.set_world_state(DAMAGE_AUTHORITY_KEY, record)
	_attach_damage_authority(record)


func on_game_state_snapshot_restored() -> void:
	if _scheduler == null or _game_state == null:
		return
	_sync_all_character_stats()
	_attach_damage_authority(_damage_authority_record())


func _on_showcase_stat_changed(char_id: String, stat: String, value: float) -> void:
	if not _characters.has(char_id):
		return
	if _hud != null:
		match stat:
			"hp", "atp":
				_hud.set_portrait_stat(char_id, stat, value)
			"stamina":
				_hud.set_portrait_stat(char_id, "sta", value)
	if stat == "hp":
		_sync_character_health_presentation(char_id)


func _on_showcase_character_downed(char_id: String) -> void:
	_sync_character_health_presentation(char_id)


func _on_showcase_character_restored(char_id: String) -> void:
	_sync_character_health_presentation(char_id)


func _sync_all_character_stats() -> void:
	if _game_state == null:
		return
	for char_id_v in _characters.keys():
		var char_id := str(char_id_v)
		if not _game_state.characters.has(char_id):
			continue
		if _hud != null:
			_hud.set_portrait_stat(char_id, "hp", _game_state.get_stat(char_id, "hp"))
			_hud.set_portrait_stat(char_id, "sta", _game_state.get_stat(char_id, "stamina"))
			_hud.set_portrait_stat(char_id, "atp", _game_state.get_stat(char_id, "atp"))
		_sync_character_health_presentation(char_id)


func _sync_character_health_presentation(char_id: String) -> void:
	if not _characters.has(char_id) or not _game_state.characters.has(char_id):
		return
	var hp := _game_state.get_stat(char_id, "hp")
	var downed := hp <= 0.0 or _game_state.is_downed(char_id)
	if _hud != null:
		_hud.set_portrait_stat(char_id, "hp", hp)
		_hud.set_portrait_status(char_id, "downed" if downed else "")
	var node: CharacterBody3D = _characters[char_id]
	node.set_move_enabled(not downed and char_id == _active_char_id)

func _flash_character(node: CharacterBody3D, color: Color) -> void:
	if node == null:
		return
	var _unused_color := color
	var base_scale: Vector3 = node.scale
	var tween := create_tween()
	tween.tween_property(node, "scale", base_scale * 1.06, 0.08)
	tween.tween_property(node, "scale", base_scale, 0.18)

func _on_enemy_hit(target_id: String, damage: float) -> void:
	_enemy_hit_log.append({
		"target_id": target_id,
		"damage": damage,
		"tick": _scheduler.get_current_tick(),
	})
	# Enemy._resolve_strike already committed this exact damage through GameState before emitting
	# hit_target. This listener is presentation/instrumentation only; applying damage here again was
	# a showroom-only second simulation.
	_sync_character_health_presentation(target_id)
	if _hud != null and CHARACTER_DISPLAY_NAMES.has(target_id):
		_hud.show_message(
			"%s hit by enemy charge" % CHARACTER_DISPLAY_NAMES[target_id],
			1.2
		)

func _on_physics_collision(obj_id: String, collider_id: String, impulse: Vector3) -> void:
	_physics_event_log.append({
		"obj_id": obj_id,
		"collider_id": collider_id,
		"impulse": impulse,
		"tick": _scheduler.get_current_tick(),
	})

	var visual: Node3D = _physics_visuals.get(obj_id, null)
	if visual and visual.has_method("on_collision"):
		visual.on_collision(collider_id, impulse)

	if collider_id != "" and _characters.has(collider_id) and impulse.length() > 0.1:
		var damage := maxf(PHYSICS_MIN_DAMAGE, impulse.length() * 1.75)
		_apply_damage(collider_id, damage, "thrown debris")

func _on_pendulum_hit(pendulum_id: String, target_id: String, bob_velocity: Vector3) -> void:
	_pendulum_event_log.append({
		"pendulum_id": pendulum_id,
		"target_id": target_id,
		"speed": bob_velocity.length(),
		"tick": _scheduler.get_current_tick(),
	})

	if _characters.has(target_id):
		var damage := maxf(PENDULUM_MIN_DAMAGE, bob_velocity.length() * 2.0)
		_apply_damage(target_id, damage, "pendulum")
	elif _physics_visuals.has(target_id):
		var visual: Node3D = _physics_visuals[target_id]
		if visual.has_method("on_collision"):
			visual.on_collision("", bob_velocity)

func get_station_positions() -> Dictionary:
	var launcher_pos := _game_state.get_physics_position("launcher_barrel") if _game_state and _game_state.physics_objects.has("launcher_barrel") else _cell_world(LAUNCHER_BARREL_CELL, 0.0)
	var hide_run_exposed := Vector3(55.2, 0.5, _cell_world(HIDE_SHELTER_CELL, 0.5).z)
	return {
		"enemy_probe": _cell_world(ENEMY_PROBE_CELL, 0.5),
		"chain_probe": _cell_world(CHAIN_PROBE_CELL, 0.5),
		"iron_patch": _cell_world(IRON_PROBE_CELL, 0.5),
		"iron_safe": _cell_world(IRON_SAFE_CELL, 0.5),
		"flure": _cell_world(SHOWCASE_FLURE_CELL, 0.5),
		"flure_probe": _cell_world(FLURE_PROBE_CELL, 0.5),
		"hide_entry": _cell_world(HIDE_ENTRY_CELL, 0.5),
		"hide_lure": _cell_world(HIDE_LURE_CELL, 0.5),
		"hide_spot": _cell_world(HIDE_SPOT_CELL, 0.5),
		"shelter": _cell_world(HIDE_SHELTER_CELL, 0.5),
		"hide_exposed_wait": _cell_world(HIDE_EXPOSED_WAIT_CELL, 0.5),
		"hide_run_exposed": hide_run_exposed,
		"launcher": _cell_world(LAUNCHER_INTERACT_CELL, 0.5),
		"launcher_hit_probe": launcher_pos + Vector3(3.5, 0.0, 0.0),
		"pendulum_probe": PENDULUM_PROBE,
		"push_barrel": _game_state.get_physics_position("push_barrel") if _game_state and _game_state.physics_objects.has("push_barrel") else _cell_world(PUSH_BARREL_CELL, 0.0),
	}

func get_character_hp(char_id: String) -> float:
	return _game_state.get_stat(char_id, "hp") if _game_state != null else 0.0

func headless_get_anchor_positions() -> Dictionary:
	return get_station_positions()


func _character_hp_snapshot() -> Dictionary:
	var snapshot := {}
	if _game_state == null:
		return snapshot
	for char_id_v in _characters.keys():
		var char_id := str(char_id_v)
		if _game_state.characters.has(char_id):
			snapshot[char_id] = _game_state.get_stat(char_id, "hp")
	return snapshot


func headless_get_state() -> Dictionary:
	var flure_anchor: Vector3 = _cell_world(SHOWCASE_FLURE_CELL, 0.5)
	var flure_total := 0.0
	for enemy in _flure_enemies:
		if enemy and _game_state and _game_state.characters.has(enemy.char_id):
			flure_total += _game_state.get_position(enemy.char_id).distance_to(flure_anchor)

	var flure_count := maxf(1.0, float(_flure_enemies.size()))
	return {
		"active_character": _active_char_id,
		"character_hp": _character_hp_snapshot(),
		"damage_authority": _damage_authority_record(),
		"enemy": {
			"standard": {
				"state": _standard_enemy.get_state() if _standard_enemy else "",
				"target": _standard_enemy._current_target_id if _standard_enemy else "",
				"distance_to_target": _enemy_target_distance(_standard_enemy),
			},
			"chain": {
				"state": _chain_enemy.get_state() if _chain_enemy else "",
				"target": _chain_enemy._current_target_id if _chain_enemy else "",
				"distance_to_target": _enemy_target_distance(_chain_enemy),
			},
		},
		"event_counts": {
			"enemy_hits": _enemy_hit_log.size(),
			"physics": _physics_event_log.size(),
			"pendulum": _pendulum_event_log.size(),
		},
		"flure_active": _showcase_flure_active,
		"flure_avg_distance": flure_total / flure_count,
		"flure_tracking_cleared": _flure_targets_cleared(),
		"flure_tracking_restored": _flure_targets_restored(),
		"hide_phase": _hide_phase,
		"hide_last_outcome": _hide_last_outcome,
		"physics_airborne": {
			"launcher_barrel": _game_state.is_physics_airborne("launcher_barrel") if _game_state and _game_state.physics_objects.has("launcher_barrel") else false,
		},
		"physics_positions": {
			"launcher_barrel": _game_state.get_physics_position("launcher_barrel") if _game_state and _game_state.physics_objects.has("launcher_barrel") else Vector3.ZERO,
			"push_barrel": _game_state.get_physics_position("push_barrel") if _game_state and _game_state.physics_objects.has("push_barrel") else Vector3.ZERO,
		},
		"scheduler_tick": _scheduler.get_current_tick() if _scheduler else 0.0,
	}

func headless_select_character(char_id: String) -> void:
	_select_character(char_id)

func headless_set_character_position(char_id: String, pos: Vector3) -> void:
	if not _characters.has(char_id) or _game_state == null \
			or not _game_state.characters.has(char_id):
		return
	if _game_state.is_external_traversal_active(char_id):
		_game_state.cancel_external_traversal(char_id, &"fixture_placement")
	_game_state.command_stop(char_id)
	if _game_state.grid != null:
		var target_level := int(_game_state.grid.level_for_y(pos.y)) \
			if int(_game_state.grid.level_count) > 1 \
			else int(_game_state.get_character_level(char_id))
		# Same-level placement must still clear a stale vertical offset; the
		# graph floor is the authority for settled character Y.
		_game_state.set_character_level(char_id, target_level)
		pos.y = _game_state.grid.grid_to_world(
			_game_state.grid.world_to_grid(pos), target_level).y
	_game_state.snap_character_to(char_id, pos, false)
	var node: CharacterBody3D = _characters[char_id]
	# The live feet transform is a presenter of GameState. Never preserve its old
	# Y independently: doing so allowed logical-only tests to pass while the body
	# remained on another deck/height.
	node.global_position = _game_state.get_render_position(char_id)
	_game_state._recompute_all_detection_predictions()
	_game_state._recompute_physics_predictions()
	_game_state._recompute_pendulum_predictions()

func headless_set_character_hp(char_id: String, hp: float) -> void:
	if _game_state == null or not _game_state.characters.has(char_id):
		return
	var new_hp := clampf(hp, 0.0, _game_state.get_stat_cap(char_id, "hp"))
	if new_hp > 0.0 and _game_state.is_downed(char_id):
		_game_state.restore_character(char_id)
	_game_state.set_stat(char_id, "hp", new_hp, "showcase_headless_fixture")
	var record := _damage_authority_record()
	if not record.is_empty():
		var iframe_deadlines := (record.get("iframe_deadlines", {}) as Dictionary).duplicate(true)
		iframe_deadlines.erase(char_id)
		record["iframe_deadlines"] = iframe_deadlines
		_game_state.set_world_state(DAMAGE_AUTHORITY_KEY, record)
	_sync_character_health_presentation(char_id)

func activate_showcase_flure() -> void:
	_on_showcase_flure_activated()

func prime_showcase_flure_window() -> void:
	_on_showcase_flure_activated()
	headless_advance(1.0)

func activate_hide_lure() -> void:
	_on_hide_lure_activated()

func prime_hide_run_window() -> void:
	_reset_hide_encounter()
	headless_select_character("endo")
	headless_set_character_position("endo", _cell_world(HIDE_SPOT_CELL, 0.5))
	_on_hide_lure_activated()
	headless_advance(HIDE_LURE_DURATION + 0.1)

func trigger_showcase_throw() -> void:
	_trigger_showcase_throw()

func headless_reset_physics_station() -> void:
	_reset_physics_station()

func reset_hide_encounter() -> void:
	_reset_hide_encounter()

func _headless_sync_runtime(delta: float) -> void:
	for node in _characters.values():
		if node and is_instance_valid(node) and node.has_method("_physics_process"):
			node._physics_process(delta)
	for enemy in _enemy_nodes:
		if enemy and is_instance_valid(enemy):
			enemy._process(delta)
	for visual in _physics_visuals.values():
		if visual and is_instance_valid(visual) and visual.has_method("_process"):
			visual._process(delta)

func _flure_targets_cleared() -> bool:
	for enemy in _flure_enemies:
		if enemy and not enemy._detection_targets.is_empty():
			return false
	return true

func _flure_targets_restored() -> bool:
	for enemy in _flure_enemies:
		if enemy and enemy._detection_targets.size() != 3:
			return false
	return true

func _enemy_target_distance(enemy: Enemy) -> float:
	if enemy == null or not _game_state:
		return -1.0
	if not _game_state.characters.has(enemy.char_id):
		return -1.0
	var target_id := str(enemy._current_target_id)
	if target_id == "" or not _game_state.characters.has(target_id):
		return -1.0
	return _game_state.get_position(enemy.char_id).distance_to(_game_state.get_position(target_id))

func _init_grid() -> void:
	_grid = GridWorld.new()
	_grid.origin = GRID_ORIGIN
	_grid.create_room(GRID_SIZE.x, GRID_SIZE.y, true)

func _build_environment() -> void:
	var env := Node3D.new()
	env.name = "Environment"
	add_child(env)

	_hazards_root = Node3D.new()
	_hazards_root.name = "Hazards"
	env.add_child(_hazards_root)

	_mark_rect(SPAWN_RECT, GridWorld.Tile.FLOOR)
	_mark_rect(ENEMY_RECT, GridWorld.Tile.FLOOR)
	_mark_rect(CHAIN_RECT, GridWorld.Tile.FLOOR)
	_mark_rect(IRON_RECT, GridWorld.Tile.FLOOR)
	_mark_rect(PHYSICS_RECT, GridWorld.Tile.FLOOR)
	_mark_rect(FLURE_RECT, GridWorld.Tile.FLOOR)
	_mark_rect(HIDE_RECT, GridWorld.Tile.FLOOR)

	var floor := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(GRID_SIZE.x, 0.1, GRID_SIZE.y)
	floor.mesh = floor_mesh
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = FLOOR_COLOR
	floor.material_override = floor_mat
	floor.position = GRID_ORIGIN + Vector3(GRID_SIZE.x / 2.0, -0.05, GRID_SIZE.y / 2.0)
	env.add_child(floor)

	var floor_body := StaticBody3D.new()
	floor_body.position = GRID_ORIGIN + Vector3(GRID_SIZE.x / 2.0, -0.01, GRID_SIZE.y / 2.0)
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(GRID_SIZE.x, 0.02, GRID_SIZE.y)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	env.add_child(floor_body)

	for i in range(0, GRID_SIZE.x + 1, 4):
		var line := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.02, 0.002, GRID_SIZE.y)
		line.mesh = bm
		line.position = GRID_ORIGIN + Vector3(float(i), 0.002, GRID_SIZE.y / 2.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.14, 0.14, 0.16, 0.22)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		line.material_override = mat
		env.add_child(line)

	for i in range(0, GRID_SIZE.y + 1, 4):
		var line := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(GRID_SIZE.x, 0.002, 0.02)
		line.mesh = bm
		line.position = GRID_ORIGIN + Vector3(GRID_SIZE.x / 2.0, 0.002, float(i))
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.14, 0.14, 0.16, 0.22)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		line.material_override = mat
		env.add_child(line)

	var dir := DirectionalLight3D.new()
	dir.rotation_degrees = Vector3(-52, 24, 0)
	dir.light_color = Color(0.72, 0.68, 0.62)
	dir.light_energy = 0.55
	dir.shadow_enabled = true
	env.add_child(dir)

	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.03, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.18, 0.17, 0.14)
	e.ambient_light_energy = 0.35
	we.environment = e
	env.add_child(we)

	_add_wall_rect(env, Rect2i(0, 0, GRID_SIZE.x, 1))
	_add_wall_rect(env, Rect2i(0, GRID_SIZE.y - 1, GRID_SIZE.x, 1))
	_add_wall_rect(env, Rect2i(0, 0, 1, GRID_SIZE.y))
	_add_wall_rect(env, Rect2i(GRID_SIZE.x - 1, 0, 1, GRID_SIZE.y))

	_add_floor_patch(env, SPAWN_RECT, Color(0.07, 0.085, 0.1))
	_add_floor_patch(env, ENEMY_RECT, STATION_FLOOR_COLOR)
	_add_floor_patch(env, CHAIN_RECT, STATION_FLOOR_COLOR)
	_add_floor_patch(env, IRON_RECT, Color(0.08, 0.075, 0.07))
	_add_floor_patch(env, PHYSICS_RECT, STATION_FLOOR_COLOR)
	_add_floor_patch(env, FLURE_RECT, Color(0.08, 0.075, 0.07))
	_add_floor_patch(env, HIDE_RECT, Color(0.08, 0.075, 0.07))

func _build_spawn_station() -> void:
	_add_station_label("Showcase Spawn", _rect_world_center(SPAWN_RECT) + Vector3(0, 2.2, -4.5), Color(0.6, 0.75, 0.95))
	_add_box(_hazards_root, _rect_world_center(SPAWN_RECT) + Vector3(0, 0.1, 0), Vector3(SPAWN_RECT.size.x - 1.0, 0.12, SPAWN_RECT.size.y - 1.0), STATION_EDGE_COLOR)

func _build_enemy_station() -> void:
	_add_station_label("Standard Enemy", _rect_world_center(ENEMY_RECT) + Vector3(0, 2.2, -4.3), Color(0.9, 0.45, 0.35))
	_add_wall_rect(_hazards_root, Rect2i(ENEMY_RECT.position.x, ENEMY_RECT.position.y, ENEMY_RECT.size.x, 1))
	_add_wall_rect(_hazards_root, Rect2i(ENEMY_RECT.position.x, ENEMY_RECT.position.y + ENEMY_RECT.size.y - 1, ENEMY_RECT.size.x, 1))
	_add_wall_rect(_hazards_root, Rect2i(ENEMY_RECT.position.x + ENEMY_RECT.size.x - 1, ENEMY_RECT.position.y, 1, ENEMY_RECT.size.y))

	_standard_enemy = Enemy.new()
	_standard_enemy.name = "ShowcaseEnemy"
	_standard_enemy.char_id = "showcase_enemy"
	_standard_enemy.position = _cell_world(ENEMY_PATROL_A, 0.0)
	_standard_enemy.move_speed = 1.6
	_standard_enemy.detection_range = 5.0
	_standard_enemy._detection_targets = ["aster", "peris", "endo"]
	_hazards_root.add_child(_standard_enemy)
	_enemy_nodes.append(_standard_enemy)

func _build_chain_station() -> void:
	_add_station_label("Chain Enemy", _rect_world_center(CHAIN_RECT) + Vector3(0, 2.2, -4.3), Color(0.8, 0.48, 0.38))
	_add_wall_rect(_hazards_root, Rect2i(CHAIN_RECT.position.x, CHAIN_RECT.position.y, CHAIN_RECT.size.x, 1))
	_add_wall_rect(_hazards_root, Rect2i(CHAIN_RECT.position.x, CHAIN_RECT.position.y + CHAIN_RECT.size.y - 1, CHAIN_RECT.size.x, 1))
	_add_wall_rect(_hazards_root, Rect2i(CHAIN_RECT.position.x + CHAIN_RECT.size.x - 1, CHAIN_RECT.position.y, 1, CHAIN_RECT.size.y))

	for i in range(4):
		_add_box(
			_hazards_root,
			_rect_world_center(Rect2i(CHAIN_RECT.position.x + CHAIN_RECT.size.x - 2, CHAIN_RECT.position.y + 1 + i * 2, 1, 1)) + Vector3(0, 1.0, 0),
			Vector3(0.25, 2.0, 0.25),
			Color(0.12, 0.1, 0.08)
		)

	_chain_enemy = ChainEnemy.new()
	_chain_enemy.name = "ShowcaseChainEnemy"
	_chain_enemy.char_id = "showcase_chain"
	_chain_enemy.position = _cell_world(CHAIN_HEAD_CELL, 0.0)
	_chain_enemy.segment_count = 7
	_chain_enemy.segment_spacing = 0.4
	_chain_enemy.max_stretch = 0.62
	_chain_enemy.follow_speed = 8.5
	_chain_enemy.move_speed = 1.5
	_chain_enemy.detection_range = 5.5
	_chain_enemy._detection_targets = ["aster", "peris", "endo"]
	_hazards_root.add_child(_chain_enemy)
	_enemy_nodes.append(_chain_enemy)

func _build_iron_station() -> void:
	_add_station_label("Iron Bloom Floor", _rect_world_center(IRON_RECT) + Vector3(0, 2.2, -4.3), Color(0.95, 0.55, 0.32))
	_add_box(_hazards_root, _rect_world_center(IRON_RECT) + Vector3(0, 0.05, 0), Vector3(IRON_RECT.size.x - 0.8, 0.12, IRON_RECT.size.y - 0.8), Color(0.1, 0.09, 0.085))

	for rect in IRON_PATCH_RECTS:
		_mark_rect(rect, GridWorld.Tile.IRON_BLOOM)
		var center := _rect_world_center(rect) + Vector3(0, 0.03, 0)
		var patch := MeshInstance3D.new()
		var patch_mesh := BoxMesh.new()
		patch_mesh.size = Vector3(rect.size.x, 0.05, rect.size.y)
		patch.mesh = patch_mesh
		var patch_mat := StandardMaterial3D.new()
		patch_mat.albedo_color = Color(0.42, 0.18, 0.07)
		patch_mat.emission_enabled = true
		patch_mat.emission = Color(0.5, 0.18, 0.04)
		patch_mat.emission_energy_multiplier = 0.35
		patch.material_override = patch_mat
		patch.position = center
		_hazards_root.add_child(patch)

		var glow := OmniLight3D.new()
		glow.position = center + Vector3(0, 0.5, 0)
		glow.light_color = Color(0.82, 0.35, 0.12)
		glow.light_energy = 0.7
		glow.omni_range = 4.5
		_hazards_root.add_child(glow)

		_iron_patches.append({
			"pos": center,
			"size": Vector3(rect.size.x, 0.05, rect.size.y),
		})

func _build_physics_station() -> void:
	_add_station_label("Pendulum + Physics", _rect_world_center(PHYSICS_RECT) + Vector3(0, 2.2, -4.3), Color(0.75, 0.85, 0.95))
	_add_wall_rect(_hazards_root, Rect2i(PHYSICS_RECT.position.x, PHYSICS_RECT.position.y, PHYSICS_RECT.size.x, 1))
	_add_wall_rect(_hazards_root, Rect2i(PHYSICS_RECT.position.x, PHYSICS_RECT.position.y + PHYSICS_RECT.size.y - 1, PHYSICS_RECT.size.x, 1))
	_add_wall_rect(_hazards_root, Rect2i(PHYSICS_RECT.position.x + PHYSICS_RECT.size.x - 1, PHYSICS_RECT.position.y, 1, PHYSICS_RECT.size.y))

	var pendulum_root := Node3D.new()
	pendulum_root.name = "PendulumVisual"
	_hazards_root.add_child(pendulum_root)

	var anchor_marker := MeshInstance3D.new()
	var anchor_mesh := SphereMesh.new()
	anchor_mesh.radius = 0.12
	anchor_mesh.height = 0.24
	anchor_marker.mesh = anchor_mesh
	var anchor_mat := StandardMaterial3D.new()
	anchor_mat.albedo_color = Color(0.72, 0.74, 0.78)
	anchor_marker.material_override = anchor_mat
	anchor_marker.position = PENDULUM_ANCHOR
	pendulum_root.add_child(anchor_marker)

	var rope := MeshInstance3D.new()
	var rope_mat := StandardMaterial3D.new()
	rope_mat.albedo_color = Color(0.35, 0.38, 0.42)
	rope_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rope.material_override = rope_mat
	pendulum_root.add_child(rope)

	var bob := MeshInstance3D.new()
	var bob_mesh := SphereMesh.new()
	bob_mesh.radius = 0.55
	bob_mesh.height = 1.1
	bob.mesh = bob_mesh
	var bob_mat := StandardMaterial3D.new()
	bob_mat.albedo_color = Color(0.58, 0.62, 0.7)
	bob_mat.metallic = 0.75
	bob_mat.roughness = 0.22
	bob.material_override = bob_mat
	pendulum_root.add_child(bob)

	_pendulum_visuals[PENDULUM_ID] = {
		"root": pendulum_root,
		"anchor": anchor_marker,
		"rope": rope,
		"bob": bob,
	}

	_build_barrel_visual("push_barrel", _cell_world(PUSH_BARREL_CELL, 0.0), Color(0.55, 0.36, 0.16))
	_build_barrel_visual("launcher_barrel", _cell_world(LAUNCHER_BARREL_CELL, 0.0), Color(0.4, 0.48, 0.55))

	_physics_defaults["push_barrel"] = {
		"pos": _cell_world(PUSH_BARREL_CELL, 0.0),
		"radius": 0.45,
		"mass": 1.3,
		"friction": 0.55,
	}
	_physics_defaults["launcher_barrel"] = {
		"pos": _cell_world(LAUNCHER_BARREL_CELL, 0.0),
		"radius": 0.35,
		"mass": 0.4,
		"friction": 0.35,
	}

	var launcher := preload("res://scenes/game/interactable.tscn").instantiate()
	launcher.name = "PhysicsLauncher"
	launcher.description = "Launcher"
	launcher.one_shot = false
	launcher.dwell_time = 1.0
	launcher.tutorial_label = "LAUNCH"
	launcher.position = _cell_world(LAUNCHER_INTERACT_CELL, 0.0)
	launcher.interacted.connect(_trigger_showcase_throw)
	_hazards_root.add_child(launcher)
	_interactables.append(launcher)

func _build_flure_station() -> void:
	_add_station_label("Flure Arena", _rect_world_center(FLURE_RECT) + Vector3(0, 2.2, -5.8), Color(0.95, 0.72, 0.34))

	_showcase_flure_mesh = MeshInstance3D.new()
	_showcase_flure_mesh.name = "ShowcaseFlure"
	var bulb := SphereMesh.new()
	bulb.radius = 0.3
	bulb.height = 0.6
	_showcase_flure_mesh.mesh = bulb
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(0.55, 0.35, 0.12)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(0.82, 0.45, 0.18)
	bulb_mat.emission_energy_multiplier = 0.35
	bulb_mat.metallic = 0.2
	_showcase_flure_mesh.material_override = bulb_mat
	_showcase_flure_mesh.position = _cell_world(SHOWCASE_FLURE_CELL, 1.05)
	_hazards_root.add_child(_showcase_flure_mesh)

	_showcase_flure_light = OmniLight3D.new()
	_showcase_flure_light.position = _cell_world(SHOWCASE_FLURE_CELL, 1.1)
	_showcase_flure_light.light_color = Color(0.95, 0.55, 0.2)
	_showcase_flure_light.light_energy = 0.45
	_showcase_flure_light.omni_range = 8.0
	_hazards_root.add_child(_showcase_flure_light)

	_showcase_flure_interactable = preload("res://scenes/game/interactable.tscn").instantiate()
	_showcase_flure_interactable.name = "ShowcaseFlureInteract"
	_showcase_flure_interactable.description = "Flure"
	_showcase_flure_interactable.required_character = "peris"
	_showcase_flure_interactable.one_shot = false
	_showcase_flure_interactable.dwell_time = 1.0
	_showcase_flure_interactable.tutorial_label = "ACTIVATE"
	_showcase_flure_interactable.position = _cell_world(SHOWCASE_FLURE_CELL, 0.0)
	_showcase_flure_interactable.interacted.connect(_on_showcase_flure_activated)
	_hazards_root.add_child(_showcase_flure_interactable)
	_interactables.append(_showcase_flure_interactable)

	for i in range(FLURE_ENEMY_CELLS.size()):
		var enemy := Enemy.new()
		enemy.name = "FlureEnemy%d" % i
		enemy.char_id = "flure_enemy_%d" % i
		enemy.position = _cell_world(FLURE_ENEMY_CELLS[i], 0.0)
		enemy.detection_range = 5.0
		enemy.move_speed = 1.45
		enemy._detection_targets = ["aster", "peris", "endo"]
		_hazards_root.add_child(enemy)
		_enemy_nodes.append(enemy)
		_flure_enemies.append(enemy)

func _build_hide_station() -> void:
	_add_station_label("Hide / Run Encounter", _rect_world_center(HIDE_RECT) + Vector3(0, 2.2, -5.8), Color(0.75, 0.92, 0.62))
	_add_wall_rect(_hazards_root, Rect2i(HIDE_RECT.position.x, HIDE_RECT.position.y, HIDE_RECT.size.x, 1))
	_add_wall_rect(_hazards_root, Rect2i(HIDE_RECT.position.x, HIDE_RECT.position.y + HIDE_RECT.size.y - 1, HIDE_RECT.size.x, 1))

	_hide_run_lure_mesh = MeshInstance3D.new()
	var run_bulb := SphereMesh.new()
	run_bulb.radius = 0.38
	run_bulb.height = 0.76
	_hide_run_lure_mesh.mesh = run_bulb
	var run_mat := StandardMaterial3D.new()
	run_mat.albedo_color = Color(0.45, 0.28, 0.12)
	run_mat.emission_enabled = true
	run_mat.emission = Color(0.85, 0.42, 0.15)
	run_mat.emission_energy_multiplier = 0.3
	_hide_run_lure_mesh.material_override = run_mat
	_hide_run_lure_mesh.position = _cell_world(HIDE_LURE_CELL, 1.1)
	_hazards_root.add_child(_hide_run_lure_mesh)

	_hide_run_lure_light = OmniLight3D.new()
	_hide_run_lure_light.position = _cell_world(HIDE_LURE_CELL, 1.2)
	_hide_run_lure_light.light_color = Color(0.95, 0.5, 0.2)
	_hide_run_lure_light.light_energy = 0.45
	_hide_run_lure_light.omni_range = 8.0
	_hazards_root.add_child(_hide_run_lure_light)

	_hide_run_lure_interactable = preload("res://scenes/game/interactable.tscn").instantiate()
	_hide_run_lure_interactable.name = "HideRunLureInteract"
	_hide_run_lure_interactable.description = "Flure"
	_hide_run_lure_interactable.required_character = "endo"
	_hide_run_lure_interactable.one_shot = false
	_hide_run_lure_interactable.dwell_time = 1.5
	_hide_run_lure_interactable.tutorial_label = "HOLD"
	_hide_run_lure_interactable.position = _cell_world(HIDE_LURE_CELL, 0.0)
	_hide_run_lure_interactable.interacted.connect(_on_hide_lure_activated)
	_hazards_root.add_child(_hide_run_lure_interactable)
	_interactables.append(_hide_run_lure_interactable)

	var hide_rect := Rect2i(67, 24, 6, 5)
	_add_floor_patch(_hazards_root, hide_rect, Color(0.065, 0.075, 0.07))
	_add_wall_rect(_hazards_root, Rect2i(67, 28, 6, 1))
	_add_wall_rect(_hazards_root, Rect2i(67, 24, 1, 5))
	_add_wall_rect(_hazards_root, Rect2i(72, 24, 1, 5))
	_add_station_label("HIDE", _cell_world(HIDE_SPOT_CELL, 2.0), Color(0.45, 0.9, 0.62))

	var shelter_rect := Rect2i(74, 17, 7, 7)
	_add_floor_patch(_hazards_root, shelter_rect, Color(0.09, 0.085, 0.075))
	_add_wall_rect(_hazards_root, Rect2i(74, 17, 7, 1), Color(0.18, 0.17, 0.16))
	_add_wall_rect(_hazards_root, Rect2i(74, 23, 7, 1), Color(0.18, 0.17, 0.16))
	_add_wall_rect(_hazards_root, Rect2i(80, 17, 1, 7), Color(0.18, 0.17, 0.16))
	var shelter_light := OmniLight3D.new()
	shelter_light.position = _cell_world(HIDE_SHELTER_CELL, 2.0)
	shelter_light.light_color = Color(0.92, 0.74, 0.42)
	shelter_light.light_energy = 1.8
	shelter_light.omni_range = 10.0
	_hazards_root.add_child(shelter_light)
	_add_station_label("SHELTER", _cell_world(HIDE_SHELTER_CELL, 2.6), Color(0.96, 0.8, 0.48))

	for i in range(HIDE_SWARM_OFFSETS.size()):
		var swarm := MeshInstance3D.new()
		swarm.name = "HideSwarm%d" % i
		var swarm_mesh := SphereMesh.new()
		swarm_mesh.radius = 0.3
		swarm_mesh.height = 0.6
		swarm.mesh = swarm_mesh
		var swarm_mat := StandardMaterial3D.new()
		swarm_mat.albedo_color = Color(0.16, 0.12, 0.08)
		swarm_mat.emission_enabled = true
		swarm_mat.emission = Color(0.48, 0.22, 0.08)
		swarm_mat.emission_energy_multiplier = 0.6
		swarm.material_override = swarm_mat
		_hazards_root.add_child(swarm)
		_hide_swarm_units.append({
			"node": swarm,
			"x": HIDE_SWARM_CLUSTER_X + HIDE_SWARM_OFFSETS[i],
			"target_x": HIDE_SWARM_CLUSTER_X + HIDE_SWARM_OFFSETS[i],
			"z": _cell_world(HIDE_LURE_CELL, 0.6).z + sin(float(i)) * 0.8,
		})

func _setup_enemy_behaviors() -> void:
	if _standard_enemy:
		_standard_enemy.activate()
		_standard_enemy.set_patrol([
			_cell_world(ENEMY_PATROL_A, 0.0),
			_cell_world(ENEMY_PATROL_B, 0.0),
		])

	if _chain_enemy:
		_chain_enemy.set_wall_line(_cell_world(CHAIN_HEAD_CELL, 0.0), Vector3(1, 0, 0))
		_chain_enemy.activate()
		_chain_enemy.set_patrol([
			_cell_world(CHAIN_PATROL_A, 0.0),
			_cell_world(CHAIN_PATROL_B, 0.0),
		])

	for i in range(_flure_enemies.size()):
		var enemy: Enemy = _flure_enemies[i]
		enemy.activate()
		var base_pos := _cell_world(FLURE_ENEMY_CELLS[i], 0.0)
		enemy.set_patrol([
			base_pos + Vector3(-0.9, 0.0, -0.4),
			base_pos + Vector3(0.8, 0.0, 0.4),
		])

func _set_showcase_flure_active(active: bool) -> void:
	_showcase_flure_active = active
	if _showcase_flure_mesh:
		var mat := _showcase_flure_mesh.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 2.8 if active else 0.35
	if _showcase_flure_light:
		_showcase_flure_light.light_energy = 1.8 if active else 0.45

func _on_showcase_flure_activated() -> void:
	if _showcase_flure_active:
		return
	_set_showcase_flure_active(true)
	_hud.show_message("Flure active: the arena pack breaks toward the lure.", 1.8)
	_scheduler.cancel_tag("showcase_flure_expire")

	for enemy in _flure_enemies:
		if not is_instance_valid(enemy):
			continue
		enemy.set_detection_targets([])
		enemy._current_target_id = ""
		enemy._change_state("idle")
		if enemy.game_state and enemy.game_state.characters.has(enemy.char_id):
			if enemy.game_state.grid:
				enemy.game_state.command_move_to_cell(enemy.char_id, enemy.game_state.grid.world_to_grid(_cell_world(SHOWCASE_FLURE_CELL, 0.0)))
			else:
				enemy.game_state.command_move_to_pos(enemy.char_id, _cell_world(SHOWCASE_FLURE_CELL, 0.0))

	_scheduler.schedule_after(SHOWCASE_FLURE_DURATION, _on_showcase_flure_expired, "showcase_flure_expire")

func _on_showcase_flure_expired() -> void:
	_set_showcase_flure_active(false)
	for enemy in _flure_enemies:
		if not is_instance_valid(enemy):
			continue
		enemy.set_detection_targets(["aster", "peris", "endo"])
		enemy._change_state("idle")

func _reset_hide_encounter() -> void:
	if _scheduler:
		_scheduler.cancel_tag("hide_lure_expire")
		_scheduler.cancel_tag("hide_encounter_reset")
	_hide_phase = "ready"
	_hide_party_hidden = false
	_hide_lure_expire_tick = -1.0
	_hide_last_outcome = ""
	_set_hide_lure_active(false)
	for i in range(_hide_swarm_units.size()):
		var unit := _hide_swarm_units[i]
		unit["x"] = HIDE_SWARM_CLUSTER_X + HIDE_SWARM_OFFSETS[i]
		unit["target_x"] = unit["x"]
		if unit["node"]:
			unit["node"].position = Vector3(unit["x"], 0.6, unit["z"])
		_hide_swarm_units[i] = unit

func _set_hide_lure_active(active: bool) -> void:
	if _hide_run_lure_mesh:
		var mat := _hide_run_lure_mesh.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 2.5 if active else 0.3
	if _hide_run_lure_light:
		_hide_run_lure_light.light_energy = 1.9 if active else 0.45

func _on_hide_lure_activated() -> void:
	if _hide_phase in ["hide", "run"]:
		return
	_hide_phase = "hide"
	_hide_party_hidden = false
	_hide_lure_expire_tick = _scheduler.get_current_tick() + HIDE_LURE_DURATION
	_set_hide_lure_active(true)
	_scheduler.cancel_tag("hide_lure_expire")
	_scheduler.schedule_after(HIDE_LURE_DURATION, _on_hide_lure_expired, "hide_lure_expire")
	_hud.show_message("Hide until the swarm commits.", 1.6)

func _on_hide_lure_expired() -> void:
	if _hide_phase != "hide":
		return
	_set_hide_lure_active(false)
	_hide_lure_expire_tick = -1.0
	if _hide_party_hidden:
		_hide_phase = "run"
		_hud.show_message("The lure burns out. Run for shelter.", 1.6)
	else:
		_fail_hide_encounter("lure_expired_exposed")

func _fail_hide_encounter(reason: String) -> void:
	if _hide_phase not in ["hide", "run"]:
		return
	_hide_phase = "failed"
	_hide_last_outcome = reason
	_hud.show_message("The swarm catches the movement. Resetting the lane.", 1.6)
	_scheduler.cancel_tag("hide_encounter_reset")
	_scheduler.schedule_after(1.2, _reset_hide_encounter, "hide_encounter_reset")

func _complete_hide_encounter() -> void:
	if _hide_phase != "run":
		return
	_hide_phase = "safe"
	_hide_last_outcome = "success"
	_hud.show_message("Shelter reached. The encounter lane is clear.", 1.8)
	_scheduler.cancel_tag("hide_encounter_reset")
	_scheduler.schedule_after(1.6, _reset_hide_encounter, "hide_encounter_reset")

func _update_hide_encounter(delta: float, spd: float) -> void:
	if _hide_phase not in ["hide", "run"]:
		return

	var target_x := _cell_world(HIDE_LURE_CELL, 0.0).x if _hide_phase == "hide" else HIDE_SWARM_CLUSTER_X
	for i in range(_hide_swarm_units.size()):
		var unit := _hide_swarm_units[i]
		unit["target_x"] = target_x + HIDE_SWARM_OFFSETS[i]
		var dx: float = unit["target_x"] - unit["x"]
		unit["x"] += signf(dx) * minf(absf(dx), HIDE_SWARM_SPEED * delta * spd)
		if unit["node"]:
			unit["node"].position = Vector3(unit["x"], 0.6, unit["z"])
		_hide_swarm_units[i] = unit

	if not _characters.has("endo"):
		return
	var leader_pos: Vector3 = _characters["endo"].global_position
	_hide_party_hidden = leader_pos.distance_to(_cell_world(HIDE_SPOT_CELL, 0.5)) <= 2.3

	if _hide_phase == "run" and leader_pos.distance_to(_cell_world(HIDE_SHELTER_CELL, 0.5)) <= 2.4:
		_complete_hide_encounter()
		return

	if _hide_party_hidden:
		return

	for unit in _hide_swarm_units:
		if absf(unit["x"] - leader_pos.x) <= HIDE_SWARM_DETECT_RADIUS:
			_fail_hide_encounter("detected")
			return

func _trigger_showcase_throw() -> void:
	if not _game_state:
		return
	_reset_single_physics_object("launcher_barrel")
	var start_pos: Vector3 = _physics_defaults["launcher_barrel"].pos + Vector3(0, 1.2, 0)
	_game_state.throw_physics_object("launcher_barrel", PHYSICS_THROW_VELOCITY, start_pos)
	_hud.show_message("Launcher fires across the physics bay.", 1.2)

func _build_barrel_visual(id: String, pos: Vector3, color: Color) -> void:
	var root := Node3D.new()
	root.name = id.capitalize()
	root.set_script(preload("res://scripts/game/objects/physics_object_3d.gd"))
	root.position = pos

	var mesh := MeshInstance3D.new()
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.38
	barrel.bottom_radius = 0.42
	barrel.height = 0.85
	mesh.mesh = barrel
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.25
	mat.roughness = 0.55
	mesh.material_override = mat
	mesh.position.y = 0.42
	root.add_child(mesh)

	_hazards_root.add_child(root)
	_physics_visuals[id] = root

func _reset_physics_station() -> void:
	for obj_id in _physics_defaults.keys():
		_reset_single_physics_object(obj_id)

	if _game_state.pendulums.has(PENDULUM_ID):
		_game_state.unregister_pendulum(PENDULUM_ID)
	_game_state.register_pendulum(PENDULUM_ID, PENDULUM_ANCHOR, PENDULUM_LENGTH, 0.55, Vector3.FORWARD, 0.55, 0.0, 0.04)

func _reset_single_physics_object(obj_id: String) -> void:
	if _game_state.physics_objects.has(obj_id):
		_game_state.unregister_physics_object(obj_id)

	var cfg: Dictionary = _physics_defaults[obj_id]
	_game_state.register_physics_object(obj_id, cfg.pos, cfg.radius, cfg.mass, cfg.friction, true)

	var visual: Node3D = _physics_visuals[obj_id]
	visual.game_state = _game_state
	visual.obj_id = obj_id
	visual.global_position = cfg.pos

func _register_pendulum_visual(id: String, anchor: Vector3) -> void:
	if not _pendulum_visuals.has(id):
		return
	var visual: Dictionary = _pendulum_visuals[id]
	visual["anchor"].global_position = anchor

func _update_pendulum_visuals() -> void:
	if not _game_state or not _pendulum_visuals.has(PENDULUM_ID):
		return
	if not _game_state.pendulums.has(PENDULUM_ID):
		return

	var visual: Dictionary = _pendulum_visuals[PENDULUM_ID]
	var anchor: Vector3 = _game_state.pendulums[PENDULUM_ID].anchor
	var bob_pos := _game_state.get_pendulum_position(PENDULUM_ID)

	var anchor_marker: MeshInstance3D = visual["anchor"]
	var bob: MeshInstance3D = visual["bob"]
	var rope: MeshInstance3D = visual["rope"]

	anchor_marker.global_position = anchor
	bob.global_position = bob_pos

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(anchor)
	im.surface_add_vertex(bob_pos)
	im.surface_end()
	rope.mesh = im

func _cell_world(cell: Vector2i, y := 0.0) -> Vector3:
	var pos := _grid.grid_to_world(cell)
	pos.y = y
	return pos

func _rect_world_center(rect: Rect2i, y := 0.0) -> Vector3:
	return GRID_ORIGIN + Vector3(rect.position.x + rect.size.x / 2.0, y, rect.position.y + rect.size.y / 2.0)

func _mark_rect(rect: Rect2i, tile: int) -> void:
	for z in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			_grid.set_tile(x, z, tile)

func _add_floor_patch(parent: Node3D, rect: Rect2i, color: Color) -> void:
	var patch := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(rect.size.x - 0.1, 0.06, rect.size.y - 0.1)
	patch.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	patch.material_override = mat
	patch.position = _rect_world_center(rect, -0.02)
	parent.add_child(patch)

func _add_wall_rect(parent: Node3D, rect: Rect2i, color := WALL_COLOR, height := 3.0) -> void:
	_mark_rect(rect, GridWorld.Tile.WALL)
	_add_box(parent, _rect_world_center(rect, height / 2.0), Vector3(rect.size.x, height, rect.size.y), color)

func _add_box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.1
	mat.roughness = 0.8
	mesh.material_override = mat
	mesh.position = pos
	parent.add_child(mesh)

func _add_station_label(text: String, pos: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 32
	label.pixel_size = 0.01
	label.modulate = Color(color, 0.9)
	label.outline_modulate = Color(0, 0, 0, 0.55)
	label.outline_size = 5
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = pos
	_hazards_root.add_child(label)
