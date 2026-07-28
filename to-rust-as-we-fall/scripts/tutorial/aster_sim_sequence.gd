@tool
extends "res://scripts/tutorial/tutorial_sequence.gd"

## Aster simulation tutorial: movement, interaction, ATP, Ron, Tag Day.

var _has_moved := false
var _has_drunk := false
var _drink_item_id := ""
var _drink_source_trigger_consumed := 0
var _active_aster_source_receipt: Dictionary = {}

var _ron
var _ron_operation_commit_active := false
var _terminal  # Forecasting terminal interactable.
var _drink_machine  # Drink machine interactable.
var _hud  # GameHUD with ATP bar and portrait.

# Terminal screen-focus cinematic (click the terminal → camera frames the
# screen, the low-fi screen swaps for a detailed readout, then the beat ends).
const TERMINAL_FOCUS_DURATION := 3.0
# Aster reads the monitor from the CHAIR side (its real front, MEASURED from the chair node — see
# _screen_facing, not an assumed world axis; the TerminalInteract marker is placed there). The focus
# camera sits TERMINAL_FOCUS_BACK back along that same facing (behind him, over his shoulder) and RISE up,
# looking down at the screen. The panel is rotated to face the same way, so the camera reads it flat
# (parallel to the display), never edge-on.
const TERMINAL_FOCUS_BACK := 2.7
const TERMINAL_FOCUS_RISE := 1.3
var _terminal_screen_world := Vector3.ZERO
var _terminal_screen_lowfi: MeshInstance3D
var _terminal_screen_detail: Node3D
var _terminal_screen_readout: Label3D
var _terminal_prev_camera_target: Node3D
var _terminal_return_camera_state: Dictionary = {}
var _terminal_focus_active := false  # true while the screen is up (guards re-click mid-focus)

# Exploration beat (post-drink, pre-Tag-Day)
@export var show_graybox_room := false  # the imported room model is the environment; flip on for graybox dev
@export var show_high_res_room := true
var _explore_hallway_gate  # Interactable at hallway exit
# Optional-read coverage telemetry. These targets never gate the hallway.
const WORKSPACE_THREAD_REQUIRED := {
	"glass": 1,
	"paintings": 2,
	"awards": 2,
	"jstore": 2,
}
var _explore_gate_unlocked := false
var _explore_gate_fired := false
var _workspace_thread_counts: Dictionary = {}
var _workspace_zone_counts: Dictionary = {}
const HALLWAY_EXIT_CELL := Vector2i(8, 13)  # east edge of the real room, just inside the wall border

# Grid system
var _grid: GridWorld
var _renderer: GridRenderer
# The room model binding — ALL model lookups/floor/occupancy flow through this (see
# RoomModelBinder). The descriptor is the scene's single declaration of its modeled room.
var _room_binder := RoomModelBinder.new()

var _data_displays: Array[MeshInstance3D] = []

const PLACEMENT_ROOT := "ScenePlacement"
# The curated display wrapper (translucent glowing beads, runtime connector
# lines, looping idle) — NOT the raw gltf, which renders dark and inert.
const GLASS_BEAD_SCENE := preload("res://scenes/tutorial/glass_bead_game_display.tscn")

# Start below max ATP so the drink refill is visible.
const ATP_START := 6.0
const ATP_MAX := GameState.ATP_MAX_PIPS
const DRINK_AUTHORITY_KEY := "runtime:aster_sim:drink_machine"
const DRINK_AUTHORITY_VERSION := 2
const DRINK_PHASE_AVAILABLE := "available"
const DRINK_PHASE_ENDOCYTOSING := "endocytosing"
const DRINK_PHASE_CONSUMED := "consumed"
const DRINK_ENDOCYTOSIS_DURATION := 2.0
const DRINK_VISUAL_COLOR := Color(0.36, 0.86, 1.0)
const ASTER_TERMINAL_SOURCE_ID := "AsterForecastTerminal"
const ASTER_DRINK_SOURCE_ID := "AsterDrinkMachine"
const ASTER_TERMINAL_ACTION := "terminal_read"
const ASTER_DRINK_ACTION := "drink_dispense"
const ASTER_INTERACTION_POSITION_TOLERANCE := 0.35
const ASTER_INTERACTION_HEIGHT_TOLERANCE := 1.35

# The intro approach, monitor focus, and outgoing fade are observable gameplay
# phases.  Their callbacks are deliberately not serialized by EventScheduler, so
# this versioned GameState record owns the causal work and the absolute deadlines;
# camera/dialogue are only presenters reconstructed from it.
const SEQUENCE_AUTHORITY_KEY := "runtime:aster_sim:sequence_authority"
const SEQUENCE_AUTHORITY_VERSION := 2
const SEQUENCE_AUTHORITY_CONTRACT := "aster_sim_sequence_v2"

const RON_PHASE_IDLE := "idle"
const RON_PHASE_APPROACHING := "approaching"
const RON_PHASE_GREETING := "greeting"
const RON_PHASE_COMPLETE := "complete"
const RON_APPROACH_RETRY_SECONDS := 0.25
const RON_APPROACH_ARRIVAL_RADIUS := 0.2

const TERMINAL_PHASE_IDLE := "idle"
const TERMINAL_PHASE_ACTIVE := "active"
const TERMINAL_PHASE_SETTLING := "settling"
const TERMINAL_PHASE_COMPLETE := "complete"
const TERMINAL_MODE_TUTORIAL := "tutorial"
const TERMINAL_MODE_REREAD := "reread"
const TERMINAL_SETTLE_DURATION := 0.4
const TERMINAL_FOCUS_AUTHORITY_TAG := "aster_terminal_authority_focus"
const TERMINAL_SETTLE_AUTHORITY_TAG := "aster_terminal_authority_settle"

const TRANSITION_PHASE_IDLE := "idle"
const TRANSITION_PHASE_FADING := "fading"
const TRANSITION_PHASE_COMPLETE := "complete"
const TRANSITION_DURATION := 2.5
const TRANSITION_AUTHORITY_TAG := "aster_transition_authority"

# --- Virtual overrides ---

func _build_scene() -> void:
	_apply_high_res_room_visibility()
	_build_environment()
	_build_terminal()
	_build_drink_machine()

func _build_characters() -> void:
	var in_game := not Engine.is_editor_hint()

	var chars := Node3D.new()
	chars.name = "Characters"
	add_child(chars)

	_player = _create_player_character("Aster", Color(0.29, 0.62, 1.0))
	_player.position = _placement_or_grid("AsterStart", Vector2i(4, 10), 0.5)
	if in_game:
		_player.grid_world = _grid
	chars.add_child(_player)
	# Characters read small in the long room — render them at double scale. Feet sit at the node
	# origin, so scaling about it keeps them grounded; the top_level path/marker overlays are unaffected.
	_player.scale = Vector3(2, 2, 2)

	_ron = _create_npc("Ron", Color(0.7, 0.6, 0.45))
	_ron.display_name = "RON"
	_ron.position = _ron_warp_spawn()
	if in_game:
		_ron.grid_world = _grid
	chars.add_child(_ron)
	_ron.scale = Vector3(2, 2, 2)
	if in_game:
		_ron.hide_for_warp()  # unformed until the portal fires (see _start_ron_warp_in)

	if in_game:
		# Camera west of the room looking east: the 14-unit-long room lays out
		# across the screen with the scene reading the right way around (the east
		# vantage showed everything mirrored — flipped 180).
		# Full look-around (pan + rotate + zoom), but CLAMPED to the room so pan/edge-scroll can never
		# drift the view off the level (the bound is derived from the grid extent).
		_setup_game_camera(_player, Vector3(-6.5, 8, 0), true)
		_bind_camera_to_level_bounds(_grid, 1.5)

func _register_characters() -> void:
	_game_state.grid = _grid
	_register_gs_character("aster", _player, _player.move_speed, {"atp": ATP_START})
	_register_gs_character("ron", _ron, _ron.move_speed)

func _setup_ui() -> void:
	# Only the ATP bar is active in this tutorial beat.
	_hud = preload("res://scenes/ui/game_hud.tscn").instantiate()
	add_child(_hud)
	_hud.add_stat_bar("atp", Color(0.3, 0.7, 0.4), ATP_MAX, ATP_START)
	_hud.bind_game_state(_game_state, "aster")

func _begin() -> void:
	_connect_drink_authority_signals()
	_connect_sequence_authority_signals()
	_ensure_aster_interaction_sources_registered()
	if _game_state.get_world_state(DRINK_AUTHORITY_KEY, null) == null:
		_publish_drink_authority(DRINK_PHASE_AVAILABLE)
	if _game_state.get_world_state(SEQUENCE_AUTHORITY_KEY, null) == null:
		_publish_sequence_authority(_baseline_sequence_authority())
	_add_screen_effect("ChromaticAberration", preload("res://resources/chromatic_aberration.gdshader"))
	_enable_outline_preview()
	_connect_outline_feedback_sources(self)
	_apply_model_occupancy_to_grid()
	if OS.get_environment("ASTER_GRID_PROBE") == "1":
		_probe_model_vs_grid()
	if OS.get_environment("ASTER_Y_PROBE") == "1":
		for i in range(8):
			_ui_scheduler.schedule_after(0.05 * (i + 1), func():
				print("[YPROBE] aster_node=%.3f ron_node=%.3f gs_aster=%.3f grid_y=%.3f" % [
					_player.global_position.y, _ron.global_position.y,
					_game_state.get_position("aster").y, _grid.origin.y]), "yprobe")
	_start_fade_in()

func _apply_model_occupancy_to_grid() -> void:
	_room_binder.apply_occupancy()

## Diagnostic: where each model object sits vs what the grid thinks of those cells.
func _probe_model_vs_grid() -> void:
	for obj_name in ["Desk", "Shelf", "drink_machine", "glass_bead_game", "Rug", "Grate"]:
		var ab := _room_object_aabb(obj_name)
		if ab.size == Vector3.ZERO:
			print("[GRIDPROBE] %s: ABSENT" % obj_name)
			continue
		var a := _grid.world_to_grid(ab.position)
		var b := _grid.world_to_grid(ab.position + ab.size)
		var n_cells := 0
		var blocked := 0
		for cz in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
			for cx in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
				n_cells += 1
				if not _grid.is_walkable(cx, cz):
					blocked += 1
		print("[GRIDPROBE] %-16s center=%s cells=%d blocked=%d (%s..%s)" % [obj_name, str(ab.get_center()), n_cells, blocked, str(a), str(b)])

func _enable_outline_preview() -> void:
	# The textured room is ALWAYS the visible environment now (its materials carry the authored
	# emissive/normal layers). The outline post-process toggle only governs the extra edge pass —
	# it must never hide the room (it used to, leaving the sim starting in a black void of
	# perception wireframes).
	_set_imported_outline_preview_enabled(OUTLINE_POST_PROCESS_ENABLED)
	if find_child("AsterSimRoomOutlinePreview", true, false) != null:
		_perception_mode = "outline"
		return
	_setup_perception("outline", _player)

func _set_imported_outline_preview_enabled(enabled: bool) -> void:
	for preview in find_children("AsterSimRoomOutlinePreview", "MeshInstance3D", true, false):
		if preview is MeshInstance3D:
			(preview as MeshInstance3D).visible = enabled

func _on_process(_delta: float, _spd: float) -> void:
	# GameHud handles ATP updates.
	_update_fades()
	_update_show_terminal()
	_sync_drink_item_visual()
	_update_ron_approach_authority()

	for i in range(_data_displays.size()):
		var d := _data_displays[i]
		d.position.y = 1.8 + sin(Time.get_ticks_msec() * 0.001 + i * 1.5) * 0.08  # @rendering_only: data display bobbing
		d.rotation.y += _delta * 0.15

func headless_get_state() -> Dictionary:
	var state := super.headless_get_state()
	state["explore_gate_unlocked"] = _explore_gate_unlocked
	state["workspace_read_counts"] = _workspace_thread_counts.duplicate(true)
	state["workspace_read_targets"] = WORKSPACE_THREAD_REQUIRED.duplicate(true)
	state["workspace_zone_counts"] = _workspace_zone_counts.duplicate(true)
	state["workspace_reads_complete"] = _workspace_completed_thread_count()
	state["workspace_read_target_count"] = WORKSPACE_THREAD_REQUIRED.size()
	state["workspace_reads_optional"] = true
	state["aster_atp"] = _game_state.get_stat("aster", "atp") if _game_state != null else 0.0
	var drink_authority := _read_drink_authority()
	state["drink_phase"] = str(drink_authority.get("phase", DRINK_PHASE_AVAILABLE))
	state["drink_item_id"] = str(drink_authority.get("item_id", ""))
	state["drink_endocytosing"] = _game_state.is_endocytosing("aster") if _game_state != null else false
	state["has_drunk"] = _has_drunk
	state["sequence_authority"] = _sequence_authority_state()
	return state

func get_playtime_contract() -> Dictionary:
	var move_speed := maxf(float(_player.move_speed) if _player != null else GameState.WALK_SPEED, 0.1)
	var start := _contract_marker_position("AsterStart", Vector3(4.5, 0.0, 11.5))
	var terminal := _contract_marker_position("TerminalInteract", Vector3(6.4, 0.0, 7.75))
	var drink := _contract_marker_position("DrinkMachineApproach", Vector3(7.0, 0.0, 3.08))
	var hallway := _contract_marker_position("HallwayExit", Vector3(8.4, 0.0, 13.5))
	var mandatory_route_meters := _horizontal_distance(start, terminal) \
		+ _horizontal_distance(terminal, drink) + _horizontal_distance(drink, hallway)
	var mandatory_active_seconds := mandatory_route_meters / move_speed + TERMINAL_FOCUS_DURATION + 1.6
	var optional_worldbuilding_seconds := 60.0
	var meaningful_active_seconds := mandatory_active_seconds + optional_worldbuilding_seconds
	return {
		"target_id": "aster_sim",
		"meaningful_active_seconds": meaningful_active_seconds,
		"total_play_seconds": meaningful_active_seconds + 24.0,
		"max_dead_gap_seconds": 3.0,
		"max_single_mode_seconds": 30.0,
		"decision_count": 1,
		"branch_count": WORKSPACE_THREAD_REQUIRED.size(),
		"category_seconds": {
			"required_traversal_and_interaction": mandatory_active_seconds,
			"optional_worldbuilding": optional_worldbuilding_seconds,
		},
		"required_first_clear_seconds": mandatory_active_seconds,
		"target_min_seconds": 30.0,
		"target_max_seconds": 90.0,
		"modeled_first_clear_seconds": meaningful_active_seconds,
		"mandatory_route_meters": mandatory_route_meters,
		"mandatory_optional_reads": 0,
		"optional_interactable_count": WORKSPACE_THREAD_REQUIRED.size(),
		"progression_gate": "hallway",
		"free_exploration": true,
		"timing_basis": "terminal and drink teaching, direct hallway progression, plus an optional 30-90 second workspace exploration beat",
	}


func _contract_marker_position(marker_name: String, fallback: Vector3) -> Vector3:
	var marker := _placement_node(marker_name)
	return marker.global_position if marker != null else fallback

func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

func _get_speed_recipients() -> Array:
	var recipients := []
	if _terminal:
		recipients.append(_terminal)
	if _drink_machine:
		recipients.append(_drink_machine)
	return recipients

## The imported room model is the environment (the graybox is a fallback for headless/dev toggles).
## STRUCTURAL, not visual: the model's geometry drives props/occupancy/anchors even when a render
## toggle (outline post-process fallback) hides it — headless runs exercise the same data layer.
func _use_room_model() -> bool:
	return not show_graybox_room and _room_binder.active()


## All MeshInstance3Ds under the named object(s) of the room model. Multiple nodes can share a name
## (the composed export has eight "j-store" journals, two "Award N" plaques) — gather every match.
func _room_model_meshes(object_name: String) -> Array:
	return _room_binder.object_meshes([object_name])


func _room_model_meshes_multi(object_names: Array) -> Array:
	return _room_binder.object_meshes(object_names)

func _model_prop(object_names: Array) -> Dictionary:
	if show_graybox_room:
		return {}
	return _room_binder.prop(object_names)

func _room_object_aabb(object_name: String) -> AABB:
	return _room_binder.object_aabb(object_name)

func _room_object_placed(object_name: String) -> bool:
	return _room_binder.object_placed(object_name)

func _model_or_marker(object_name: String, marker_name: String, fallback_position: Vector3) -> Vector3:
	if show_graybox_room:
		return _placement_or_position(marker_name, fallback_position)
	return _room_binder.anchor(object_name, _placement_node(marker_name), fallback_position)

func _placement_node(marker_name: String) -> Node3D:
	var root := get_node_or_null(PLACEMENT_ROOT)
	if root == null:
		return null
	return root.find_child(marker_name, true, false) as Node3D

func _placement_or_position(marker_name: String, fallback_position: Vector3) -> Vector3:
	var marker := _placement_node(marker_name)
	return marker.global_position if marker != null else fallback_position

func _placement_or_grid(marker_name: String, fallback_cell: Vector2i, y: float = 0.0) -> Vector3:
	var fallback := _grid.grid_to_world(fallback_cell)
	fallback.y = y
	return _placement_or_position(marker_name, fallback)

## Ron's authored warp-in spot: the RonStartMarker placed under the room model, resolved through the
## shared spawn helper (snaps off the wall border onto a walkable, grounded cell). Falls back to the
## old RonStart marker / grid cell if it's missing.
func _ron_warp_spawn() -> Vector3:
	return _spawn_at_marker(_grid, "RonStartMarker", _placement_or_grid("RonStart", Vector2i(3, 12), _grid.origin.y))

func _local_for_parent(parent: Node3D, world_pos: Vector3) -> Vector3:
	return parent.to_local(world_pos) if parent != null else world_pos

func _apply_high_res_room_visibility() -> void:
	var high_res_scene := find_child("AsterRoom", true, false) as Node3D
	if high_res_scene != null:
		high_res_scene.visible = show_high_res_room
		var high_res_room := high_res_scene.find_child("default", true, false) as Node3D
		if high_res_room != null:
			high_res_room.visible = show_high_res_room
		for light in high_res_scene.find_children("*", "Light3D", true, false):
			if light is Light3D:
				(light as Light3D).visible = show_high_res_room
	else:
		var high_res_room := find_child("default", true, false) as Node3D
		if high_res_room != null:
			high_res_room.visible = show_high_res_room
		var high_res_spot := find_child("SpotLight3D", true, false) as Light3D
		if high_res_spot != null:
			high_res_spot.visible = show_high_res_room

func _create_graybox_outline_target(
		parent: Node3D,
		target_name: String,
		center: Vector3,
		size: Vector3,
		meshes: Array,
		element_id: String,
		radius: float = 1.0
	) -> Node3D:
	# Thin wrapper over the shared base helper, kept for the existing call sites.
	return _create_outline_target(parent, target_name, center, size, meshes, element_id, radius)

# --- Per-frame visual helpers ---

func _update_fades() -> void:
	if _current_step == "fade_in":
		_update_fade_in(2.0)
	elif _current_step == "transition_out":
		_update_fade_out(Color(0.05, 0.03, 0.01), 2.0)

func _update_show_terminal() -> void:
	if _current_step == "show_terminal" and not _has_moved and _player.is_moving():
		_has_moved = true
		_terminal.hide_tutorial_label()


# --- Portable sequence authority ---------------------------------------------------------------

func _baseline_sequence_authority() -> Dictionary:
	return {
		"version": SEQUENCE_AUTHORITY_VERSION,
		"contract": SEQUENCE_AUTHORITY_CONTRACT,
		"ron": _baseline_ron_authority(),
		"terminal": _baseline_terminal_authority(),
		"transition": _baseline_transition_authority(),
	}


func _baseline_ron_authority() -> Dictionary:
	return {
		"phase": RON_PHASE_IDLE,
		"started_at": -1.0,
		"arrived_at": -1.0,
		"completed_at": -1.0,
		"endpoint": [],
		"next_retry_tick": -1.0,
		"operation_counter": 0,
		"active_operation_id": "",
		"operations": [],
		"interruptions": [],
	}


func _baseline_terminal_authority() -> Dictionary:
	return {
		"phase": TERMINAL_PHASE_IDLE,
		"mode": "",
		"started_at": -1.0,
		"deadline": -1.0,
		"tutorial_complete": false,
		"return_move_enabled": true,
		"return_camera": {},
		"source_data_id": ASTER_TERMINAL_SOURCE_ID,
		"source_trigger_count": 0,
	}


func _baseline_transition_authority() -> Dictionary:
	return {
		"phase": TRANSITION_PHASE_IDLE,
		"started_at": -1.0,
		"deadline": -1.0,
		"completed_at": -1.0,
		"camera": {},
		"move_enabled_before": true,
	}


func _sequence_authority_state() -> Dictionary:
	if _game_state == null:
		return {}
	var raw: Variant = _game_state.get_world_state(SEQUENCE_AUTHORITY_KEY, null)
	if not (raw is Dictionary):
		return {}
	var authority := raw as Dictionary
	var version := int(authority.get("version", 0))
	var contract := str(authority.get("contract", ""))
	if version == 1 and contract == "aster_sim_sequence_v1":
		authority = _migrate_aster_sequence_authority_v1(authority)
	elif version != SEQUENCE_AUTHORITY_VERSION \
			or contract != SEQUENCE_AUTHORITY_CONTRACT:
		return {}
	return authority.duplicate(true)


func _migrate_aster_sequence_authority_v1(raw: Dictionary) -> Dictionary:
	var migrated := raw.duplicate(true)
	migrated["version"] = SEQUENCE_AUTHORITY_VERSION
	migrated["contract"] = SEQUENCE_AUTHORITY_CONTRACT
	var terminal: Dictionary = migrated.get("terminal", {})
	terminal["source_data_id"] = ASTER_TERMINAL_SOURCE_ID
	# Version 1 already knew whether the focus was active/complete, but it did not
	# own an exact source edge. Burn all registry history visible in that snapshot
	# so an old trigger can never masquerade as a new physical read.
	terminal["source_trigger_count"] = maxi(
		0, _aster_source_trigger_count(_terminal))
	migrated["terminal"] = terminal
	return migrated


func _publish_sequence_authority(authority: Dictionary) -> void:
	if _game_state == null:
		return
	authority["version"] = SEQUENCE_AUTHORITY_VERSION
	authority["contract"] = SEQUENCE_AUTHORITY_CONTRACT
	_game_state.set_world_state(SEQUENCE_AUTHORITY_KEY, authority.duplicate(true))


func _sequence_authority_section(section: String) -> Dictionary:
	var authority := _sequence_authority_state()
	var value: Variant = authority.get(section, null)
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _publish_sequence_authority_section(section: String, value: Dictionary) -> void:
	var authority := _sequence_authority_state()
	if authority.is_empty():
		authority = _baseline_sequence_authority()
	authority[section] = value.duplicate(true)
	_publish_sequence_authority(authority)


func _authority_v3_data(value: Variant) -> Array:
	if not (value is Vector3) or not (value as Vector3).is_finite():
		return []
	var vector := value as Vector3
	return [vector.x, vector.y, vector.z]


func _authority_v3(value: Variant) -> Vector3:
	if not (value is Array) or (value as Array).size() != 3:
		return Vector3.INF
	var encoded := value as Array
	for component in encoded:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT] \
				or not is_finite(float(component)):
			return Vector3.INF
	var result := Vector3(float(encoded[0]), float(encoded[1]), float(encoded[2]))
	return result if result.is_finite() else Vector3.INF


func _authority_finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


func _authority_transform_data(value: Transform3D) -> Dictionary:
	return {
		"basis_x": _authority_v3_data(value.basis.x),
		"basis_y": _authority_v3_data(value.basis.y),
		"basis_z": _authority_v3_data(value.basis.z),
		"origin": _authority_v3_data(value.origin),
	}


func _authority_transform(value: Variant) -> Transform3D:
	if not (value is Dictionary):
		return Transform3D.IDENTITY
	var encoded := value as Dictionary
	var basis_x := _authority_v3(encoded.get("basis_x", null))
	var basis_y := _authority_v3(encoded.get("basis_y", null))
	var basis_z := _authority_v3(encoded.get("basis_z", null))
	var origin := _authority_v3(encoded.get("origin", null))
	if not basis_x.is_finite() or not basis_y.is_finite() \
			or not basis_z.is_finite() or not origin.is_finite():
		return Transform3D.IDENTITY
	return Transform3D(Basis(basis_x, basis_y, basis_z), origin)


func _capture_authority_camera_state() -> Dictionary:
	if _camera == null:
		return {}
	var view: Dictionary = (
		_camera.capture_view_state() if _camera.has_method("capture_view_state") else {}
	)
	var target_id := ""
	var target: Variant = view.get("target", _camera.target)
	if target == _player:
		target_id = "aster"
	elif target == _ron:
		target_id = "ron"
	var lock_override: Variant = view.get("lock_offset_override", null)
	var transform_v: Variant = view.get("global_transform", _camera.global_transform)
	var transform: Transform3D = (
		transform_v as Transform3D if transform_v is Transform3D else _camera.global_transform
	)
	return {
		"target_id": target_id,
		"follow_offset": _authority_v3_data(view.get("follow_offset", _camera.follow_offset)),
		"pan_offset": _authority_v3_data(view.get("pan_offset", Vector3.ZERO)),
		"view_yaw": float(view.get("view_yaw", 0.0)),
		"view_zoom": float(view.get("view_zoom", 1.0)),
		"locked": bool(view.get("locked", false)),
		"lock_position": _authority_v3_data(view.get("lock_position", Vector3.ZERO)),
		"lock_offset_override": (
			_authority_v3_data(lock_override as Vector3) if lock_override is Vector3 else null
		),
		"global_transform": _authority_transform_data(transform),
	}


func _valid_authority_camera_state(value: Variant) -> bool:
	if not (value is Dictionary):
		return false
	var state := value as Dictionary
	for required_key in [
		"target_id", "follow_offset", "pan_offset", "view_yaw", "view_zoom",
		"locked", "lock_position", "lock_offset_override", "global_transform",
	]:
		if not state.has(required_key):
			return false
	if str(state.get("target_id", "")) not in ["", "aster", "ron"]:
		return false
	if not (state.get("target_id", null) is String) \
			or not (state.get("locked", null) is bool):
		return false
	for key in ["follow_offset", "pan_offset", "lock_position"]:
		if not _authority_v3(state.get(key, null)).is_finite():
			return false
	var lock_override: Variant = state.get("lock_offset_override", null)
	if lock_override != null and not _authority_v3(lock_override).is_finite():
		return false
	var yaw_v: Variant = state.get("view_yaw", null)
	var zoom_v: Variant = state.get("view_zoom", null)
	if not _authority_finite_number(yaw_v) or not _authority_finite_number(zoom_v):
		return false
	var yaw := float(yaw_v)
	var zoom := float(zoom_v)
	var transform_v: Variant = state.get("global_transform", null)
	if not is_finite(yaw) or not is_finite(zoom) or zoom <= 0.0 or zoom > 10.0 \
			or not (transform_v is Dictionary):
		return false
	var transform := transform_v as Dictionary
	for key in ["basis_x", "basis_y", "basis_z", "origin"]:
		if not _authority_v3(transform.get(key, null)).is_finite():
			return false
	if absf(_authority_transform(transform).basis.determinant()) <= 0.0001:
		return false
	return true


func _apply_authority_camera_state(encoded: Dictionary) -> void:
	if _camera == null or not _valid_authority_camera_state(encoded):
		return
	var target: Node3D = null
	match str(encoded.get("target_id", "")):
		"aster":
			target = _player
		"ron":
			target = _ron
	var lock_override: Variant = encoded.get("lock_offset_override", null)
	var decoded := {
		"target": target,
		"follow_offset": _authority_v3(encoded.get("follow_offset", null)),
		"pan_offset": _authority_v3(encoded.get("pan_offset", null)),
		"view_yaw": float(encoded.get("view_yaw", 0.0)),
		"view_zoom": float(encoded.get("view_zoom", 1.0)),
		"global_transform": _authority_transform(encoded.get("global_transform", null)),
		"locked": bool(encoded.get("locked", false)),
		"lock_position": _authority_v3(encoded.get("lock_position", null)),
		"lock_offset_override": (
			_authority_v3(lock_override) if lock_override != null else null
		),
	}
	if _camera.has_method("restore_view_state"):
		_camera.restore_view_state(decoded)
	else:
		_camera.target = target
		_camera.follow_offset = decoded["follow_offset"]
		_camera.unlock()


func _connect_sequence_authority_signals() -> void:
	if _game_state == null:
		return
	if not _game_state.character_arrived.is_connected(_on_aster_sim_character_arrived):
		_game_state.character_arrived.connect(_on_aster_sim_character_arrived)


func _ron_approach_endpoint() -> Vector3:
	# Aster cannot move during the intro, so the authored spawn is the stable causal
	# context. Using his later live position here would mutate the historical endpoint
	# after he walks to the terminal and make an otherwise valid old receipt fail load.
	var aster_position := _placement_or_grid("AsterStart", Vector2i(4, 10), _grid.origin.y)
	var desired := aster_position + Vector3(1.5, 0.0, 0.5)
	if _grid != null:
		desired = _grid.nearest_walkable_world(desired)
	return desired


func _ron_is_at_approach_endpoint(record: Dictionary) -> bool:
	if _game_state == null or not _game_state.characters.has("ron") \
			or _game_state.is_moving("ron"):
		return false
	var endpoint := _authority_v3(record.get("endpoint", null))
	return endpoint.is_finite() \
		and _game_state.get_position("ron").distance_to(endpoint) <= RON_APPROACH_ARRIVAL_RADIUS


func _ron_has_accepted_approach_receipt(record: Dictionary) -> bool:
	var endpoint := _authority_v3(record.get("endpoint", null))
	if not endpoint.is_finite():
		return false
	var operations_v: Variant = record.get("operations", null)
	if not (operations_v is Array):
		return false
	for operation_v in operations_v as Array:
		if not (operation_v is Dictionary):
			continue
		var operation := operation_v as Dictionary
		if bool(operation.get("accepted", false)) \
				and str(operation.get("actor_id", "")) == "ron" \
				and str(operation.get("kind", "")) == "move_to_pos" \
				and _authority_v3(operation.get("endpoint", null)).distance_to(endpoint) \
					<= RON_APPROACH_ARRIVAL_RADIUS:
			return true
	return false


func _valid_ron_authority(record: Dictionary) -> bool:
	var phase := str(record.get("phase", ""))
	if phase == RON_PHASE_IDLE:
		return _authority_finite_number(record.get("started_at", null)) \
			and _authority_finite_number(record.get("next_retry_tick", null)) \
			and float(record.get("started_at", -1.0)) < 0.0 \
			and float(record.get("next_retry_tick", -1.0)) < 0.0
	if phase not in [RON_PHASE_APPROACHING, RON_PHASE_GREETING, RON_PHASE_COMPLETE]:
		return false
	var endpoint := _authority_v3(record.get("endpoint", null))
	var canonical_endpoint := _ron_approach_endpoint()
	var started_v: Variant = record.get("started_at", null)
	if not _authority_finite_number(started_v):
		return false
	var started_at := float(started_v)
	if not endpoint.is_finite() or endpoint.distance_to(canonical_endpoint) \
			> RON_APPROACH_ARRIVAL_RADIUS or not is_finite(started_at) or started_at < 0.0:
		return false
	var operations_v: Variant = record.get("operations", null)
	var interruptions_v: Variant = record.get("interruptions", null)
	if not (operations_v is Array) or not (interruptions_v is Array) \
			or int(record.get("operation_counter", -1)) < 0:
		return false
	for operation_v in operations_v as Array:
		if not (operation_v is Dictionary):
			return false
		var operation := operation_v as Dictionary
		if str(operation.get("operation_id", "")) == "" \
				or str(operation.get("actor_id", "")) != "ron" \
				or str(operation.get("kind", "")) != "move_to_pos" \
				or not (operation.get("accepted", null) is bool) \
				or _authority_v3(operation.get("endpoint", null)).distance_to(endpoint) \
					> RON_APPROACH_ARRIVAL_RADIUS \
				or not _authority_finite_number(operation.get("committed_at", null)):
			return false
	for interruption_v in interruptions_v as Array:
		if not (interruption_v is Dictionary):
			return false
		var interruption := interruption_v as Dictionary
		if str(interruption.get("operation_id", "")) == "" \
				or not _authority_finite_number(interruption.get("observed_at", null)) \
				or not _authority_v3(interruption.get("position", null)).is_finite():
			return false
	if phase == RON_PHASE_APPROACHING:
		var retry_v: Variant = record.get("next_retry_tick", null)
		if not _authority_finite_number(retry_v):
			return false
		var retry := float(retry_v)
		return is_finite(retry) and retry >= started_at
	if not _ron_has_accepted_approach_receipt(record):
		return false
	var arrived_v: Variant = record.get("arrived_at", null)
	if not _authority_finite_number(arrived_v):
		return false
	var arrived_at := float(arrived_v)
	if not is_finite(arrived_at) or arrived_at < started_at \
			or float(record.get("next_retry_tick", -1.0)) >= 0.0:
		return false
	if phase == RON_PHASE_COMPLETE:
		var completed_v: Variant = record.get("completed_at", null)
		if not _authority_finite_number(completed_v):
			return false
		var completed_at := float(completed_v)
		return is_finite(completed_at) and completed_at >= arrived_at
	return true


func _valid_terminal_authority(record: Dictionary) -> bool:
	var phase := str(record.get("phase", ""))
	if not _authority_finite_number(record.get("started_at", null)) \
			or not _authority_finite_number(record.get("deadline", null)) \
			or not (record.get("tutorial_complete", null) is bool) \
			or str(record.get("source_data_id", "")) != ASTER_TERMINAL_SOURCE_ID \
			or int(record.get("source_trigger_count", -1)) < 0:
		return false
	var started_at := float(record.get("started_at", -1.0))
	var deadline := float(record.get("deadline", -1.0))
	match phase:
		TERMINAL_PHASE_IDLE:
			return started_at < 0.0 and deadline < 0.0 \
				and not bool(record.get("tutorial_complete", true))
		TERMINAL_PHASE_ACTIVE:
			var mode := str(record.get("mode", ""))
			return mode in [TERMINAL_MODE_TUTORIAL, TERMINAL_MODE_REREAD] \
				and is_finite(started_at) and is_finite(deadline) \
				and started_at >= 0.0 and deadline > started_at \
				and (record.get("return_move_enabled", null) is bool) \
				and _valid_authority_camera_state(record.get("return_camera", null)) \
				and (mode == TERMINAL_MODE_REREAD) \
					== bool(record.get("tutorial_complete", false))
		TERMINAL_PHASE_SETTLING:
			return str(record.get("mode", "")) == TERMINAL_MODE_TUTORIAL \
				and is_finite(started_at) and is_finite(deadline) \
				and started_at >= 0.0 and deadline > started_at \
				and not bool(record.get("tutorial_complete", true)) \
				and (record.get("return_move_enabled", null) is bool) \
				and _valid_authority_camera_state(record.get("return_camera", null))
		TERMINAL_PHASE_COMPLETE:
			return started_at >= 0.0 and deadline < 0.0 \
				and bool(record.get("tutorial_complete", false))
		_:
			return false


func _valid_transition_authority(record: Dictionary) -> bool:
	var phase := str(record.get("phase", ""))
	if not _authority_finite_number(record.get("started_at", null)) \
			or not _authority_finite_number(record.get("deadline", null)):
		return false
	var started_at := float(record.get("started_at", -1.0))
	var deadline := float(record.get("deadline", -1.0))
	match phase:
		TRANSITION_PHASE_IDLE:
			return started_at < 0.0 and deadline < 0.0
		TRANSITION_PHASE_FADING:
			return is_finite(started_at) and is_finite(deadline) \
				and started_at >= 0.0 and deadline > started_at \
				and (record.get("move_enabled_before", null) is bool) \
				and _valid_authority_camera_state(record.get("camera", null))
		TRANSITION_PHASE_COMPLETE:
			var completed_v: Variant = record.get("completed_at", null)
			if not _authority_finite_number(completed_v):
				return false
			var completed_at := float(completed_v)
			return is_finite(started_at) and is_finite(deadline) \
				and is_finite(completed_at) and started_at >= 0.0 \
				and deadline > started_at and completed_at >= deadline \
				and (record.get("move_enabled_before", null) is bool) \
				and _valid_authority_camera_state(record.get("camera", null))
		_:
			return false


# --- Exact Aster interaction sources ----------------------------------------------------------

func _ensure_aster_interaction_sources_registered() -> void:
	_configure_aster_interaction_source(
		_terminal, ASTER_TERMINAL_SOURCE_ID, ASTER_TERMINAL_ACTION)
	_configure_aster_interaction_source(
		_drink_machine, ASTER_DRINK_SOURCE_ID, ASTER_DRINK_ACTION)


func _configure_aster_interaction_source(
		source: Node, data_id: String, action_id: String) -> void:
	if _game_state == null or not is_instance_valid(source):
		return
	if not _game_state.has_interactable(data_id):
		var source_position := (
			(source as Node3D).global_position if source is Node3D else Vector3.ZERO
		)
		var source_type := int(source.get("interactable_type"))
		_game_state.register_interactable({
			"id": data_id,
			"position": source_position,
			"requires_hold": source_type == Interactable.InteractableType.HOLD_ACTION,
			"interactable_type": source_type,
			"hold_time": float(source.get("dwell_time")),
			"one_shot": true,
			"required_character": "aster",
			"radius": float(source.get("interaction_radius")),
			"tutorial_label": str(source.get("tutorial_label")),
			"catalog_id": str(source.get("interactable_id")),
			"enabled": bool(source.get("interaction_enabled")),
		})
	if source.has_method("bind_data"):
		source.call("bind_data", _game_state, data_id)
	source.set("one_shot", true)
	source.set("required_character", "aster")
	if source.has_method("set_pre_trigger_validator"):
		source.call(
			"set_pre_trigger_validator",
			_validate_aster_source_trigger.bind(action_id, source)
		)


func _validate_aster_source_trigger(
		source: Node, actor: String, action_id: String, expected_source: Node) -> bool:
	return is_instance_valid(source) and source == expected_source \
		and (
			(action_id == ASTER_TERMINAL_ACTION and source == _terminal)
			or (action_id == ASTER_DRINK_ACTION and source == _drink_machine)
		) \
		and _aster_actor_ready_at_source(source, actor) \
		and _aster_source_action_ready(action_id)


func _aster_actor_ready_at_source(source: Node, actor: String) -> bool:
	if _game_state == null or not is_instance_valid(source) or not (source is Node3D) \
			or actor != "aster" or not _game_state.characters.has(actor) \
			or not _game_state.is_narratively_available(actor) \
			or _game_state.is_downed(actor) or _game_state.is_knocked_down(actor) \
			or _game_state.is_moving(actor) or _game_state.is_resting(actor) \
			or _game_state.is_dodging(actor) or _game_state.is_endocytosing(actor) \
			or _game_state.is_external_traversal_active(actor) \
			or _game_state.is_dragging(actor) or _game_state.is_field_restoring(actor) \
			or _game_state.is_pushing(actor):
		return false
	var source_position := (source as Node3D).global_position
	if _game_state.grid != null and _game_state.grid.level_count > 1 \
			and int(_game_state.get_character_level(actor)) != int(
				_game_state.grid.level_for_y(source_position.y)):
		return false
	var actor_position := _game_state.get_position(actor)
	var radius := float(source.get("interaction_radius")) \
		+ ASTER_INTERACTION_POSITION_TOLERANCE
	return Vector2(actor_position.x, actor_position.z).distance_to(
		Vector2(source_position.x, source_position.z)) <= radius \
		and absf(actor_position.y - source_position.y) \
			<= ASTER_INTERACTION_HEIGHT_TOLERANCE


func _aster_source_action_ready(action_id: String) -> bool:
	if action_id == ASTER_TERMINAL_ACTION:
		if _terminal_focus_active:
			return false
		var terminal := _sequence_authority_section("terminal")
		var phase := str(terminal.get("phase", TERMINAL_PHASE_IDLE))
		return (
			_current_step == "show_terminal" and phase == TERMINAL_PHASE_IDLE
		) or (
			_terminal_story_has_passed() and phase == TERMINAL_PHASE_COMPLETE
		)
	if action_id != ASTER_DRINK_ACTION:
		return false
	var drink_phase := str(
		_read_drink_authority().get("phase", DRINK_PHASE_AVAILABLE))
	if drink_phase == DRINK_PHASE_AVAILABLE:
		return _current_step == "walk_to_drink" \
			and _game_state.has_free_hands("aster")
	return drink_phase == DRINK_PHASE_CONSUMED or _has_drunk


func _aster_source_trigger_count(source: Node) -> int:
	if _game_state == null or not is_instance_valid(source):
		return -1
	var data_id := str(source.get("data_id"))
	if data_id == "" or not _game_state.has_interactable(data_id):
		return -1
	return int(_game_state.get_interactable(data_id).get("trigger_count", -1))


func _aster_source_receipt(
		source: Node, action_id: String, consumed_count: int) -> Dictionary:
	if not is_instance_valid(source):
		return {}
	var actor := str(source.get("active_character"))
	if not _validate_aster_source_trigger(source, actor, action_id, source) \
			or not bool(source.get("one_shot")) or not bool(source.get("_used")) \
			or bool(source.get("interaction_enabled")):
		return {}
	var data_id := str(source.get("data_id"))
	if data_id == "" or not _game_state.has_interactable(data_id):
		return {}
	var registry := _game_state.get_interactable(data_id)
	var trigger_count := int(registry.get("trigger_count", -1))
	if not bool(registry.get("one_shot", false)) \
			or not bool(registry.get("triggered", false)) \
			or bool(registry.get("enabled", true)) \
			or str(registry.get("last_trigger_character", "")) != actor \
			or trigger_count != consumed_count + 1:
		return {}
	return {
		"action": action_id,
		"source_data_id": data_id,
		"actor": actor,
		"trigger_count": trigger_count,
	}


func _aster_source_receipt_is_active(
		receipt: Dictionary, action_id: String, source: Node) -> bool:
	return not receipt.is_empty() \
		and receipt == _active_aster_source_receipt \
		and str(receipt.get("action", "")) == action_id \
		and str(receipt.get("source_data_id", "")) == str(source.get("data_id")) \
		and str(receipt.get("actor", "")) == "aster" \
		and int(receipt.get("trigger_count", -1)) \
			== _aster_source_trigger_count(source)


func _set_aster_source_projection(source: Node, enabled: bool) -> void:
	if _game_state == null or not is_instance_valid(source):
		return
	var data_id := str(source.get("data_id"))
	if data_id != "" and _game_state.has_interactable(data_id):
		var registry := _game_state.get_interactable(data_id)
		if enabled and bool(registry.get("triggered", false)):
			# Owner-derived rearm: reset clears only the one-shot spent bit. Its
			# trigger_count remains the monotonic receipt identity.
			source.call("reset")
		elif bool(registry.get("enabled", true)) != enabled:
			_game_state.set_interactable_enabled(data_id, enabled)
	if source.has_method("restore_one_shot_presenter"):
		source.call("restore_one_shot_presenter", false, enabled)
	elif source.has_method("set_interaction_enabled"):
		source.call("set_interaction_enabled", enabled)

# --- Event-driven steps ---

func _start_fade_in() -> void:
	_enter_step("fade_in")
	_player.set_move_enabled(false)
	_fade_from(Color(0, 0, 0, 1), 2.5, _start_working, "working")

func _start_working() -> void:
	_enter_step("working")
	# Brief settle after the fade, then Ron warps in (no long dead-air idle).
	_schedule_portable_method(0.5, _start_ron_warp_in, "ron_warp_in")

func _start_ron_warp_in() -> void:
	_enter_step("ron_warp_in")
	# Ron arrives through a portal: a cosmetic flash at his marker + his body materializing. The
	# logical hand-off to the approach rides the scheduler (a tween never gates a step).
	if _ron != null:
		var portal := WarpPortal.new()
		add_child(portal)
		portal.global_position = Vector3(_ron.global_position.x, _grid.origin.y, _ron.global_position.z)
		portal.play(WarpPortal.GREEN, 1.4)
		if _ron.has_method("warp_in"):
			_ron.warp_in(1.3)
	_schedule_portable_method(1.3, _start_ron_approaches, "ron_approaches")

func _start_ron_approaches() -> void:
	_enter_step("ron_approaches")
	_hide_thought()
	_player.set_move_enabled(false)
	_restore_ron_post_warp_presenter()
	var now := float(_scheduler.get_current_tick())
	var record := _baseline_ron_authority()
	record["phase"] = RON_PHASE_APPROACHING
	record["started_at"] = now
	record["endpoint"] = _authority_v3_data(_ron_approach_endpoint())
	record["next_retry_tick"] = now
	_publish_sequence_authority_section("ron", record)
	_update_ron_approach_authority()

func _start_ron_greeting() -> void:
	var record := _sequence_authority_section("ron")
	if not _valid_ron_authority(record):
		return
	var phase := str(record.get("phase", ""))
	if phase == RON_PHASE_APPROACHING:
		if not _ron_has_accepted_approach_receipt(record) \
				or not _ron_is_at_approach_endpoint(record):
			return
		record["phase"] = RON_PHASE_GREETING
		record["arrived_at"] = float(_scheduler.get_current_tick())
		record["next_retry_tick"] = -1.0
		record["active_operation_id"] = ""
		_publish_sequence_authority_section("ron", record)
	elif phase != RON_PHASE_GREETING:
		return
	_present_ron_greeting()


func _present_ron_greeting() -> void:
	_enter_step("ron_greeting")
	_player.set_move_enabled(false)
	_restore_ron_post_warp_presenter()
	_clear_dialogue_presenter_for_restore()
	_dialogue_chain(
		["aster_sim.ron.greeting", "aster_sim.ron.name"],
		_on_ron_greeting_finished
	)


func _on_ron_greeting_finished() -> void:
	var record := _sequence_authority_section("ron")
	if not _valid_ron_authority(record) \
			or str(record.get("phase", "")) != RON_PHASE_GREETING:
		return
	# Presentation cannot launder an interrupted approach.  If another system moved
	# Ron during the greeting, return to the same saved endpoint and only greet once
	# his body is physically there again.
	if not _ron_is_at_approach_endpoint(record):
		record["phase"] = RON_PHASE_APPROACHING
		record["arrived_at"] = -1.0
		record["next_retry_tick"] = float(_scheduler.get_current_tick())
		_publish_sequence_authority_section("ron", record)
		_enter_step("ron_approaches")
		return
	record["phase"] = RON_PHASE_COMPLETE
	record["completed_at"] = float(_scheduler.get_current_tick())
	_publish_sequence_authority_section("ron", record)
	_start_show_terminal()


func _on_aster_sim_character_arrived(char_id: String) -> void:
	if char_id == "ron" and not _ron_operation_commit_active:
		_update_ron_approach_authority()


func _restore_ron_post_warp_presenter() -> void:
	if _ron == null or not is_instance_valid(_ron):
		return
	if _ron.has_method("_set_warp_dissolve"):
		_ron.call("_set_warp_dissolve", 1.05)
	var label: Node = _ron.get_node_or_null("Label3D")
	if label is Label3D:
		(label as Label3D).modulate.a = 0.7


func _update_ron_approach_authority() -> void:
	if _game_state == null or _scheduler == null:
		return
	var record := _sequence_authority_section("ron")
	if not _valid_ron_authority(record) \
			or str(record.get("phase", "")) != RON_PHASE_APPROACHING:
		return
	if _ron_is_at_approach_endpoint(record):
		if _ron_has_accepted_approach_receipt(record):
			_start_ron_greeting()
		else:
			var now_without_receipt := float(_scheduler.get_current_tick())
			if now_without_receipt + 0.000001 \
					>= float(record.get("next_retry_tick", now_without_receipt)):
				_issue_ron_approach_operation(record)
		return
	var endpoint := _authority_v3(record.get("endpoint", null))
	var active_operation_id := str(record.get("active_operation_id", ""))
	var movement_matches := _game_state.is_moving("ron") \
		and _game_state.get_destination("ron").distance_to(endpoint) \
			<= RON_APPROACH_ARRIVAL_RADIUS
	if movement_matches:
		return
	if active_operation_id != "":
		var interruptions := (record.get("interruptions", []) as Array).duplicate(true)
		interruptions.append({
			"operation_id": active_operation_id,
			"observed_at": float(_scheduler.get_current_tick()),
			"reason": "destination_replaced" if _game_state.is_moving("ron") else "stopped_early",
			"position": _authority_v3_data(_game_state.get_position("ron")),
		})
		record["interruptions"] = interruptions
		record["active_operation_id"] = ""
		_publish_sequence_authority_section("ron", record)
	var now := float(_scheduler.get_current_tick())
	if now + 0.000001 < float(record.get("next_retry_tick", now)):
		return
	_issue_ron_approach_operation(record)


func _issue_ron_approach_operation(record: Dictionary) -> void:
	if _game_state == null or _scheduler == null:
		return
	var endpoint := _authority_v3(record.get("endpoint", null))
	if not endpoint.is_finite():
		return
	var attempt := int(record.get("operation_counter", 0)) + 1
	var operation_id := "ron_approach:%d" % attempt
	var accepted := false
	var rejection := "movement_locked"
	if _game_state.can_accept_move_command("ron"):
		_ron_operation_commit_active = true
		accepted = _game_state.command_move_to_pos("ron", endpoint)
		_ron_operation_commit_active = false
		if accepted:
			accepted = (
				(_game_state.is_moving("ron")
					and _game_state.get_destination("ron").distance_to(endpoint)
						<= RON_APPROACH_ARRIVAL_RADIUS)
				or _ron_is_at_approach_endpoint(record)
			)
			rejection = "" if accepted else "endpoint_not_committed"
		else:
			rejection = "command_rejected"
	var operations := (record.get("operations", []) as Array).duplicate(true)
	operations.append({
		"operation_id": operation_id,
		"actor_id": "ron",
		"kind": "move_to_pos",
		"accepted": accepted,
		"rejection": rejection,
		"committed_at": float(_scheduler.get_current_tick()),
		"endpoint": _authority_v3_data(endpoint),
	})
	record["operations"] = operations
	record["operation_counter"] = attempt
	record["active_operation_id"] = operation_id if accepted else ""
	record["next_retry_tick"] = float(_scheduler.get_current_tick()) \
		+ RON_APPROACH_RETRY_SECONDS
	_publish_sequence_authority_section("ron", record)
	if _ron_is_at_approach_endpoint(record):
		_start_ron_greeting()

func _start_show_terminal() -> void:
	_enter_step("show_terminal")
	# The TerminalInteract marker sits in FRONT of the monitor (the chair side), so the interaction walks
	# Aster there to read it face-on instead of standing at the side of the desk.
	if _terminal and _terminal.has_method("set_interaction_enabled"):
		_terminal.set_interaction_enabled(true)
	_terminal.show_tutorial_label()
	_player.set_move_enabled(true)
	# Terminal interaction triggers _on_terminal_interacted (signal-driven)

func _on_terminal_interacted() -> void:
	if _terminal_focus_active:
		return
	var record := _sequence_authority_section("terminal")
	var receipt := _aster_source_receipt(
		_terminal,
		ASTER_TERMINAL_ACTION,
		int(record.get("source_trigger_count", 0))
	)
	if receipt.is_empty():
		return
	record["source_data_id"] = ASTER_TERMINAL_SOURCE_ID
	record["source_trigger_count"] = int(receipt.get("trigger_count", 0))
	_publish_sequence_authority_section("terminal", record)
	_active_aster_source_receipt = receipt
	if _current_step == "show_terminal":
		_scheduler.cancel_tag("drink_redirect")
		# The controller already walked Aster to the reading spot (queued glow on the desk in his colour
		# while en route); the FIRST read drives the tutorial forward.
		_start_terminal_focus_from_source_receipt(receipt)
	else:
		# Later reads just re-show the screen — the monitor stays readable, but the tutorial doesn't move.
		_replay_terminal_focus_from_source_receipt(receipt)
	_active_aster_source_receipt.clear()

# Aster has reached the terminal's reading spot → frame the screen from the FRONT, swap in the detailed
# readout, hold a beat, then continue. Scheduler-driven so it runs headless and respects F.
func _start_terminal_focus() -> void:
	# Retired automation seam. The exact terminal receipt owns every real read.
	pass


func _start_terminal_focus_from_source_receipt(receipt: Dictionary) -> void:
	_begin_terminal_focus_authority(TERMINAL_MODE_TUTORIAL, receipt)

func _end_terminal_focus() -> void:
	var record := _sequence_authority_section("terminal")
	_on_terminal_authority_deadline(
		str(record.get("phase", "")),
		str(record.get("mode", "")),
		float(record.get("deadline", -1.0))
	)

## Re-read the monitor after the tutorial has moved past it: same screen + framing, but no step change
## and no progression — purely a look.
func _replay_terminal_focus() -> void:
	# Retired automation seam. A reread still requires Aster at the terminal.
	pass


func _replay_terminal_focus_from_source_receipt(receipt: Dictionary) -> void:
	_begin_terminal_focus_authority(TERMINAL_MODE_REREAD, receipt)

func _end_terminal_reread() -> void:
	_end_terminal_focus()


func _begin_terminal_focus_authority(mode: String, source_receipt: Dictionary = {}) -> void:
	if _scheduler == null or mode not in [TERMINAL_MODE_TUTORIAL, TERMINAL_MODE_REREAD]:
		return
	if not _aster_source_receipt_is_active(
			source_receipt, ASTER_TERMINAL_ACTION, _terminal):
		return
	var existing := _sequence_authority_section("terminal")
	if int(existing.get("source_trigger_count", -1)) \
			!= int(source_receipt.get("trigger_count", -2)):
		return
	if mode == TERMINAL_MODE_TUTORIAL:
		if _valid_terminal_authority(existing) \
				and bool(existing.get("tutorial_complete", false)):
			return
		_enter_step("terminal_focus")
	else:
		if not _valid_terminal_authority(existing) \
				or not bool(existing.get("tutorial_complete", false)):
			return
	var now := float(_scheduler.get_current_tick())
	var record := _baseline_terminal_authority()
	record["phase"] = TERMINAL_PHASE_ACTIVE
	record["mode"] = mode
	record["started_at"] = now
	record["deadline"] = now + TERMINAL_FOCUS_DURATION
	record["tutorial_complete"] = mode == TERMINAL_MODE_REREAD
	record["return_move_enabled"] = (
		bool(_player.is_move_enabled()) if _player != null \
			and _player.has_method("is_move_enabled") else true
	)
	record["return_camera"] = _capture_authority_camera_state()
	record["source_data_id"] = ASTER_TERMINAL_SOURCE_ID
	record["source_trigger_count"] = int(source_receipt.get("trigger_count", 0))
	_publish_sequence_authority_section("terminal", record)
	_apply_terminal_focus_presenter(record)
	_arm_terminal_authority(record)


func _apply_terminal_focus_presenter(record: Dictionary) -> void:
	_terminal_return_camera_state = (
		(record.get("return_camera", {}) as Dictionary).duplicate(true)
	)
	if _player != null:
		_player.set_move_enabled(false)
	_begin_terminal_screen_focus(_terminal_return_camera_state)


func _arm_terminal_authority(record: Dictionary, currently_firing_tag := "") -> void:
	if _scheduler == null:
		return
	# The shipped native scheduler's pop-next path retires its live-count after
	# invoking the callback. Cancelling that currently firing handle from inside
	# itself would double-retire it and hide the newly chained callback from
	# pending_count(), even though the heap still contains it.
	if currently_firing_tag != TERMINAL_FOCUS_AUTHORITY_TAG:
		_scheduler.cancel_tag(TERMINAL_FOCUS_AUTHORITY_TAG)
	if currently_firing_tag != TERMINAL_SETTLE_AUTHORITY_TAG:
		_scheduler.cancel_tag(TERMINAL_SETTLE_AUTHORITY_TAG)
	# Retire the old local tags as well, so a same-presenter rollback cannot keep a
	# callback from the discarded future alive.
	_scheduler.cancel_tag("terminal_focus")
	_scheduler.cancel_tag("terminal_reread")
	var phase := str(record.get("phase", ""))
	if phase not in [TERMINAL_PHASE_ACTIVE, TERMINAL_PHASE_SETTLING]:
		return
	var mode := str(record.get("mode", ""))
	var deadline := float(record.get("deadline", -1.0))
	var now := float(_scheduler.get_current_tick())
	if deadline <= now:
		_on_terminal_authority_deadline(phase, mode, deadline)
	else:
		var authority_tag := TERMINAL_FOCUS_AUTHORITY_TAG \
			if phase == TERMINAL_PHASE_ACTIVE else TERMINAL_SETTLE_AUTHORITY_TAG
		_scheduler.schedule_at(
			deadline,
			_on_terminal_authority_deadline.bind(phase, mode, deadline),
			authority_tag
		)


func _on_terminal_authority_deadline(
		expected_phase: String,
		expected_mode: String,
		expected_deadline: float
	) -> void:
	var record := _sequence_authority_section("terminal")
	if not _valid_terminal_authority(record) \
			or str(record.get("phase", "")) != expected_phase \
			or str(record.get("mode", "")) != expected_mode \
			or not is_equal_approx(float(record.get("deadline", -1.0)), expected_deadline):
		return
	if expected_phase == TERMINAL_PHASE_ACTIVE:
		_end_terminal_screen_focus(record.get("return_camera", {}) as Dictionary)
		if _player != null:
			_player.set_move_enabled(bool(record.get("return_move_enabled", true)))
		if expected_mode == TERMINAL_MODE_REREAD:
			record["phase"] = TERMINAL_PHASE_COMPLETE
			record["mode"] = ""
			record["deadline"] = -1.0
			record["return_camera"] = {}
			_publish_sequence_authority_section("terminal", record)
			_rearm_interactable(_terminal)
			return
		_start_terminal_data(record, TERMINAL_FOCUS_AUTHORITY_TAG)
		return
	if expected_phase != TERMINAL_PHASE_SETTLING:
		return
	record["phase"] = TERMINAL_PHASE_COMPLETE
	record["mode"] = ""
	record["deadline"] = -1.0
	record["tutorial_complete"] = true
	record["return_camera"] = {}
	_publish_sequence_authority_section("terminal", record)
	_rearm_interactable(_terminal)
	_start_ron_drinks()

## Re-arm a one-shot interactable so it can be used again (its trigger disabled it). Safe for a
## HOLD_ACTION too: the dwell only re-fires on a fresh body-enter, so re-arming while the character is
## still standing in range does not immediately re-trigger.
func _rearm_interactable(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.has_method("reset"):
		node.reset()
	if node.has_method("set_interaction_enabled"):
		node.set_interaction_enabled(true)

## The horizontal unit direction the desk monitor FACES — toward the chair, where someone sits to read
## it. Measured from the actual chair node so the framing matches the modeled desk instead of an assumed
## axis (the monitor faces +X here, not +Z). Falls back to +X if the chair can't be found.
func _screen_facing() -> Vector3:
	var chair := find_child("*hair*", true, false) as Node3D
	if chair != null:
		var f: Vector3 = chair.global_position - _terminal_screen_world
		f.y = 0.0
		if f.length() > 0.05:
			return f.normalized()
	return Vector3(1, 0, 0)

func _begin_terminal_screen_focus(return_camera_state: Dictionary = {}) -> void:
	_terminal_focus_active = true
	if return_camera_state.is_empty():
		_terminal_return_camera_state = _capture_authority_camera_state()
	else:
		_terminal_return_camera_state = return_camera_state.duplicate(true)
	if _terminal_screen_lowfi != null:
		_terminal_screen_lowfi.visible = false
	var facing := _screen_facing()
	if _terminal_screen_detail != null:
		_terminal_screen_detail.visible = true
		# Turn the readable panel to face the chair (the real monitor's front) so the camera reads it flat.
		_terminal_screen_detail.rotation.y = atan2(facing.x, facing.z)
	# Hide Aster's floating nameplate so it doesn't dominate the tight screen shot.
	var label = _player.get_node_or_null("Label3D") if _player != null else null
	if label != null:
		label.visible = false
	if _camera != null:
		var target_id := str(_terminal_return_camera_state.get("target_id", ""))
		_terminal_prev_camera_target = _player if target_id == "aster" else (
			_ron if target_id == "ron" else null
		)
		# Sit the camera back along the monitor's facing (on the chair side) and a little up, looking at
		# the screen head-on — parallel to the display, not edge-on. Fixed override so it ignores whatever
		# gameplay angle the player left the camera at.
		var off := facing * TERMINAL_FOCUS_BACK + Vector3(0.0, TERMINAL_FOCUS_RISE, 0.0)
		_camera.lock_to(_terminal_screen_world, off)

func _end_terminal_screen_focus(return_camera_state: Dictionary = {}) -> void:
	_terminal_focus_active = false
	if _terminal_screen_detail != null:
		_terminal_screen_detail.visible = false
	if _terminal_screen_lowfi != null:
		_terminal_screen_lowfi.visible = true
	var label = _player.get_node_or_null("Label3D") if _player != null else null
	if label != null:
		label.visible = true
	var saved_camera := return_camera_state
	if saved_camera.is_empty():
		saved_camera = _terminal_return_camera_state
	if _camera != null:
		if _valid_authority_camera_state(saved_camera):
			_apply_authority_camera_state(saved_camera)
		else:
			_camera.target = _terminal_prev_camera_target
			_camera.unlock()
	_terminal_return_camera_state.clear()

func _start_terminal_data(
		active_record: Dictionary = {},
		currently_firing_tag := ""
	) -> void:
	_enter_step("terminal_data")
	# Brief beat for the screen-focus camera to settle back before Ron pipes up.
	var record := active_record.duplicate(true)
	if record.is_empty():
		record = _sequence_authority_section("terminal")
	if not _valid_terminal_authority(record) \
			or str(record.get("phase", "")) != TERMINAL_PHASE_ACTIVE \
			or str(record.get("mode", "")) != TERMINAL_MODE_TUTORIAL:
		return
	var now := float(_scheduler.get_current_tick())
	record["phase"] = TERMINAL_PHASE_SETTLING
	record["started_at"] = now
	record["deadline"] = now + TERMINAL_SETTLE_DURATION
	_publish_sequence_authority_section("terminal", record)
	_arm_terminal_authority(record, currently_firing_tag)

func _start_ron_drinks() -> void:
	_enter_step("ron_drinks")
	# Ron points out the drink machine BEFORE the prompt appears, so grabbing a drink reads as a
	# response to him rather than coming out of nowhere. The prompt opens as he finishes the line.
	_dialogue_chain(["aster_sim.ron.drinks"], _start_walk_to_drink)

func _start_walk_to_drink() -> void:
	_enter_step("walk_to_drink")
	if _drink_machine and _drink_machine.has_method("set_interaction_enabled"):
		_drink_machine.set_interaction_enabled(true)
	_drink_machine.show_tutorial_label()
	# Presentation-only hint if the player skips the drink too long. Losing this callback on load
	# cannot unlock, complete, or otherwise mutate the drink/story authority.
	_scheduler.schedule_after(8.0, _show_drink_redirect, "drink_redirect")

func _show_drink_redirect() -> void:
	if not _has_drunk and _current_step == "walk_to_drink":
		_show_thought(DialogueData.text("aster_sim.drink_redirect.thought"))

func _on_drink_interacted() -> void:
	var authority := _read_drink_authority()
	var phase := str(authority.get("phase", DRINK_PHASE_AVAILABLE))
	var receipt := _aster_source_receipt(
		_drink_machine, ASTER_DRINK_ACTION, _drink_source_trigger_consumed)
	if receipt.is_empty():
		return
	_drink_source_trigger_consumed = int(receipt.get("trigger_count", 0))
	_publish_drink_authority(
		phase, str(authority.get("item_id", "")))
	_active_aster_source_receipt = receipt
	if phase == DRINK_PHASE_AVAILABLE and _current_step == "walk_to_drink":
		# First drink: dispense a real lysate item, put it in Aster's hand, and let the
		# canonical endocytosis state own both the two-second action and the ATP change.
		_scheduler.cancel_tag("drink_redirect")
		_start_drink_from_source_receipt(receipt)
	elif phase == DRINK_PHASE_CONSUMED or _has_drunk:
		# Already topped up — Aster waves it off, with a glance toward Tag Day.
		_show_thought(DialogueData.text("aster_sim.drink_again.thought"))
		_rearm_interactable(_drink_machine)
	_active_aster_source_receipt.clear()

func _start_drink() -> void:
	# Retired automation seam. Dispensing begins only from the exact machine edge.
	pass


func _start_drink_from_source_receipt(source_receipt: Dictionary) -> void:
	if not _aster_source_receipt_is_active(
			source_receipt, ASTER_DRINK_ACTION, _drink_machine):
		return
	var authority := _read_drink_authority()
	var phase := str(authority.get("phase", DRINK_PHASE_AVAILABLE))
	if phase == DRINK_PHASE_CONSUMED:
		_has_drunk = true
		_rearm_interactable(_drink_machine)
		return
	if phase == DRINK_PHASE_ENDOCYTOSING:
		_drink_item_id = str(authority.get("item_id", ""))
		if _drink_machine != null and _drink_machine.has_method("set_interaction_enabled"):
			_drink_machine.set_interaction_enabled(false)
		_sync_drink_item_visual()
		return
	if _game_state == null or not _game_state.has_free_hands("aster"):
		_show_drink_failure("Aster needs a free hand for the drink.")
		_rearm_interactable(_drink_machine)
		return
	_enter_step("drink")
	_hide_thought()
	if _drink_machine != null and _drink_machine.has_method("set_interaction_enabled"):
		_drink_machine.set_interaction_enabled(false)
	var aster_position := _game_state.get_position("aster")
	_drink_item_id = spawn_preview_item("lysate", aster_position, {
		"display_name": "Machine Lysate",
		"atp_restore": maxf(0.0, ATP_MAX - _game_state.get_stat("aster", "atp")),
		"endocytosis_duration": DRINK_ENDOCYTOSIS_DURATION,
		"aster_drink_authority": DRINK_AUTHORITY_KEY,
	})
	if _drink_item_id == "" or not pick_up_preview_item("aster", _drink_item_id):
		_abort_drink_dispense("The machine cannot place the drink in Aster's hand.")
		return
	if not endocytose_preview_item("aster", _drink_item_id):
		_abort_drink_dispense("Aster cannot drink while another action owns movement.")
		return
	_publish_drink_authority(DRINK_PHASE_ENDOCYTOSING, _drink_item_id)
	_sync_drink_item_visual()


func _connect_drink_authority_signals() -> void:
	if _game_state == null:
		return
	if not _game_state.item_endocytosed.is_connected(_on_drink_item_endocytosed):
		_game_state.item_endocytosed.connect(_on_drink_item_endocytosed)


func _publish_drink_authority(phase: String, item_id := "") -> void:
	if _game_state == null:
		return
	_game_state.set_world_state(DRINK_AUTHORITY_KEY, {
		"version": DRINK_AUTHORITY_VERSION,
		"authority_id": DRINK_AUTHORITY_KEY,
		"phase": phase,
		"item_id": item_id,
		"source_data_id": ASTER_DRINK_SOURCE_ID,
		"source_trigger_count": _drink_source_trigger_consumed,
	})


func _read_drink_authority() -> Dictionary:
	var baseline := {
		"version": DRINK_AUTHORITY_VERSION,
		"authority_id": DRINK_AUTHORITY_KEY,
		"phase": DRINK_PHASE_AVAILABLE,
		"item_id": "",
		"source_data_id": ASTER_DRINK_SOURCE_ID,
		"source_trigger_count": _drink_source_trigger_consumed,
	}
	var result := baseline
	if _game_state != null:
		var raw: Variant = _game_state.get_world_state(DRINK_AUTHORITY_KEY, null)
		var saved_source_count := _drink_source_trigger_consumed
		if raw is Dictionary:
			var raw_record := raw as Dictionary
			var raw_version := int(raw_record.get("version", 0))
			if raw_version == DRINK_AUTHORITY_VERSION \
					and str(raw_record.get("authority_id", "")) == DRINK_AUTHORITY_KEY \
					and str(raw_record.get("source_data_id", "")) == ASTER_DRINK_SOURCE_ID:
				saved_source_count = maxi(
					0, int(raw_record.get("source_trigger_count", 0)))
			elif raw_version == 1 \
					and str(raw_record.get("authority_id", "")) == DRINK_AUTHORITY_KEY:
				# Version 1 knew the item/phase but not the source edge. Burn
				# every trigger visible in that save before accepting a new one.
				saved_source_count = maxi(
					0, _aster_source_trigger_count(_drink_machine))
		_drink_source_trigger_consumed = saved_source_count
		# The in-flight action has one authority, not two: the tagged GameState item in
		# Aster's hand plus GameState's saved endocytosis timer. The world record is the
		# semantic receipt, but losing/corrupting that receipt cannot erase already-paid
		# action time or let a reload skip to the consumed endpoint.
		var active_item_id := _active_aster_drink_item_id()
		if active_item_id != "":
			result = {
				"version": DRINK_AUTHORITY_VERSION,
				"authority_id": DRINK_AUTHORITY_KEY,
				"phase": DRINK_PHASE_ENDOCYTOSING,
				"item_id": active_item_id,
				"source_data_id": ASTER_DRINK_SOURCE_ID,
				"source_trigger_count": saved_source_count,
			}
		else:
			if raw is Dictionary:
				var saved := raw as Dictionary
				var phase := str(saved.get("phase", ""))
				var item_id := str(saved.get("item_id", ""))
				var valid_receipt := (
					int(saved.get("version", 0)) in [1, DRINK_AUTHORITY_VERSION]
					and str(saved.get("authority_id", "")) == DRINK_AUTHORITY_KEY
					and phase in [DRINK_PHASE_AVAILABLE, DRINK_PHASE_CONSUMED]
					and item_id == ""
				)
				if valid_receipt:
					result = baseline.duplicate(true)
					result["phase"] = phase
					result["source_trigger_count"] = saved_source_count
	return result


func _active_aster_drink_item_id() -> String:
	if _game_state == null or not _game_state.is_endocytosing("aster"):
		return ""
	for item_id_variant in _game_state.get_hand_items("aster"):
		var item_id := str(item_id_variant)
		if not _game_state.items.has(item_id):
			continue
		var item := _game_state.items[item_id] as Dictionary
		var properties := item.get("properties", {}) as Dictionary
		if str(properties.get("aster_drink_authority", "")) == DRINK_AUTHORITY_KEY \
				and str(item.get("holder", "")) == "aster" \
				and str(item.get("location", "")) == "hand":
			return item_id
	return ""


func _on_drink_item_endocytosed(char_id: String, item_id: String, effect: String) -> void:
	if char_id != "aster" or item_id == "":
		return
	var raw: Variant = _game_state.get_world_state(DRINK_AUTHORITY_KEY, null)
	var receipt_matches := raw is Dictionary \
			and str((raw as Dictionary).get("item_id", "")) == item_id
	if item_id != _drink_item_id and not receipt_matches:
		return
	if effect != "digest":
		_drink_item_id = ""
		_retire_drink_item_visual(item_id)
		_publish_drink_authority(DRINK_PHASE_AVAILABLE)
		_rearm_interactable(_drink_machine)
		_start_walk_to_drink()
		_show_drink_failure("That was not a usable drink. The machine is ready to try again.")
		return
	_drink_item_id = ""
	_retire_drink_item_visual(item_id)
	_publish_drink_authority(DRINK_PHASE_CONSUMED)
	_has_drunk = true
	_rearm_interactable(_drink_machine)
	if _current_step == "drink":
		_start_ron_move_fast()


func _abort_drink_dispense(message: String) -> void:
	var failed_item_id := _drink_item_id
	_drink_item_id = ""
	if failed_item_id != "":
		remove_preview_item(failed_item_id)
	_publish_drink_authority(DRINK_PHASE_AVAILABLE)
	_has_drunk = false
	_rearm_interactable(_drink_machine)
	_start_walk_to_drink()
	_show_drink_failure(message)


func _show_drink_failure(message: String) -> void:
	if _hud != null and _hud.has_method("show_message"):
		_hud.show_message(message, 2.4)
	elif _tutorial_prompt != null and _tutorial_prompt.has_method("show_prompt"):
		_tutorial_prompt.show_prompt(message, 2.4)


func _retire_drink_item_visual(item_id: String) -> void:
	if not _chunk_item_nodes.has(item_id):
		return
	var node: Node3D = _chunk_item_nodes[item_id]
	if is_instance_valid(node):
		node.queue_free()
	_chunk_item_nodes.erase(item_id)


func _sync_drink_item_visual() -> void:
	if _drink_item_id == "" or _game_state == null:
		return
	if not _game_state.items.has(_drink_item_id):
		_retire_drink_item_visual(_drink_item_id)
		_drink_item_id = ""
		return
	_ensure_chunk_item_node(_drink_item_id)
	var node := _chunk_item_nodes.get(_drink_item_id) as Node3D
	if node == null or not is_instance_valid(node):
		return
	var material: StandardMaterial3D = null
	if node is MeshInstance3D:
		material = (node as MeshInstance3D).material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = DRINK_VISUAL_COLOR
		material.emission = DRINK_VISUAL_COLOR.lightened(0.1)
	var item := _game_state.items[_drink_item_id] as Dictionary
	if str(item.get("location", "ground")) == "hand" and str(item.get("holder", "")) == "aster":
		var aster_world := _game_state.get_render_position("aster")
		node.global_position = aster_world + Vector3(0.42, 1.05, 0.10)
		var tick := _scheduler.get_current_tick() if _scheduler != null else 0.0
		var pulse := 1.0 + sin(tick * 8.0) * 0.08
		node.scale = Vector3.ONE * pulse
	else:
		var item_position: Vector3 = item.get("position", Vector3.ZERO)
		node.global_position = item_position + Vector3(0.0, 0.42, 0.0)
		node.scale = Vector3.ONE


func on_game_state_snapshot_restored() -> void:
	_connect_drink_authority_signals()
	_connect_sequence_authority_signals()
	_ensure_aster_interaction_sources_registered()
	_reconcile_aster_interaction_source_receipts()
	var previous_item_id := _drink_item_id
	var authority := _read_drink_authority()
	var phase := str(authority.get("phase", DRINK_PHASE_AVAILABLE))
	_drink_item_id = str(authority.get("item_id", "")) if phase == DRINK_PHASE_ENDOCYTOSING else ""
	_has_drunk = phase == DRINK_PHASE_CONSUMED
	if previous_item_id != "" and previous_item_id != _drink_item_id:
		_retire_drink_item_visual(previous_item_id)
	if phase == DRINK_PHASE_ENDOCYTOSING:
		_restore_drink_machine_presenter(false)
		_sync_drink_item_visual()
	else:
		if phase == DRINK_PHASE_AVAILABLE and _current_step == "drink":
			# An absent/rejected authority record cannot retain a future story step.
			_current_step = "walk_to_drink"
		_restore_drink_machine_presenter(
			phase == DRINK_PHASE_CONSUMED or _current_step == "walk_to_drink"
		)
	_restore_sequence_authority_after_snapshot()


func _reconcile_aster_interaction_source_receipts() -> void:
	if _game_state == null:
		return
	var sequence_authority := _sequence_authority_state()
	if not sequence_authority.is_empty():
		var raw_sequence: Variant = _game_state.get_world_state(
			SEQUENCE_AUTHORITY_KEY, null)
		var terminal: Dictionary = sequence_authority.get("terminal", {})
		var terminal_source_count := maxi(
			0, _aster_source_trigger_count(_terminal))
		var terminal_committed := maxi(
			0, int(terminal.get("source_trigger_count", 0)))
		var sequence_changed := not (raw_sequence is Dictionary) \
			or int((raw_sequence as Dictionary).get("version", 0)) \
				!= SEQUENCE_AUTHORITY_VERSION
		if terminal_source_count > terminal_committed:
			# Snapshot seam: Interactable accepted Aster synchronously but the
			# terminal owner had not begun. Burn that edge without showing data.
			terminal["source_trigger_count"] = terminal_source_count
			terminal["source_data_id"] = ASTER_TERMINAL_SOURCE_ID
			sequence_authority["terminal"] = terminal
			sequence_changed = true
		if sequence_changed:
			_publish_sequence_authority(sequence_authority)

	var raw_drink: Variant = _game_state.get_world_state(DRINK_AUTHORITY_KEY, null)
	var active_item_id := _active_aster_drink_item_id()
	var drink := _read_drink_authority()
	var drink_source_count := maxi(
		0, _aster_source_trigger_count(_drink_machine))
	var drink_changed := raw_drink is Dictionary \
		and int((raw_drink as Dictionary).get("version", 0)) \
			!= DRINK_AUTHORITY_VERSION
	if drink_source_count != _drink_source_trigger_consumed:
		# A newer count is the accepted-before-owner seam; a lower count means
		# snapshot absence/legacy registration retracted later history. In both
		# directions the registry in this save is the next receipt baseline.
		_drink_source_trigger_consumed = drink_source_count
		drink["source_trigger_count"] = drink_source_count
		drink_changed = raw_drink is Dictionary
	if drink_changed or active_item_id != "" and not (raw_drink is Dictionary):
		_publish_drink_authority(
			str(drink.get("phase", DRINK_PHASE_AVAILABLE)),
			str(drink.get("item_id", ""))
		)


func _restore_sequence_authority_after_snapshot() -> void:
	if _scheduler == null or _game_state == null:
		return
	_cancel_sequence_authority_callbacks()
	# A same-presenter rollback may still be showing a focus from the discarded
	# future.  Retire it through its saved return view before inspecting the older
	# record, so the old lock cannot become the new baseline camera.
	if _terminal_focus_active:
		_end_terminal_screen_focus()
	_clear_dialogue_presenter_for_restore()
	if _sequence_authority_state().is_empty():
		_publish_sequence_authority(_baseline_sequence_authority())
	_restore_ron_authority_after_snapshot()
	_restore_terminal_authority_after_snapshot()
	_restore_transition_authority_after_snapshot()


func _cancel_sequence_authority_callbacks() -> void:
	if _scheduler == null:
		return
	for tag in [
		TERMINAL_FOCUS_AUTHORITY_TAG,
		TERMINAL_SETTLE_AUTHORITY_TAG,
		TRANSITION_AUTHORITY_TAG,
		"terminal_focus",
		"terminal_reread",
		"ron_greeting",
		"complete",
	]:
		_scheduler.cancel_tag(tag)


func _clear_dialogue_presenter_for_restore() -> void:
	if _dialogue == null:
		return
	for connection_v in _dialogue.dialogue_finished.get_connections():
		var connection := connection_v as Dictionary
		_dialogue.dialogue_finished.disconnect(connection.callable)
	_dialogue.clear()
	_dlg_chain_keys.clear()
	_dlg_chain_index = 0
	_dlg_chain_next = Callable()
	_dlg_chain_delay = 0.0


func _ron_story_has_passed() -> bool:
	return _current_step in [
		"show_terminal", "terminal_focus", "terminal_data", "ron_drinks",
		"walk_to_drink", "drink", "ron_move_fast", "explore_workspace",
		"tag_notify", "walk_to_exit", "transition_out", "complete",
	]


func _restore_ron_authority_after_snapshot() -> void:
	var record := _sequence_authority_section("ron")
	if not _valid_ron_authority(record):
		_repair_ron_authority_for_saved_step()
		return
	var phase := str(record.get("phase", ""))
	if phase != RON_PHASE_IDLE:
		_restore_ron_post_warp_presenter()
	match phase:
		RON_PHASE_APPROACHING:
			if _current_step not in ["ron_approaches", "ron_greeting"]:
				_repair_ron_authority_for_saved_step()
				return
			_current_step = "ron_approaches"
			_player.set_move_enabled(false)
			_update_ron_approach_authority()
		RON_PHASE_GREETING:
			if _current_step not in ["ron_approaches", "ron_greeting"] \
					or not _ron_is_at_approach_endpoint(record):
				_restart_ron_approach_from_physical_state(record)
				return
			_present_ron_greeting()
		RON_PHASE_COMPLETE:
			if not _ron_story_has_passed():
				_restart_ron_approach_from_physical_state(record)
		RON_PHASE_IDLE:
			if _current_step in ["ron_approaches", "ron_greeting"]:
				_restart_ron_approach_from_physical_state(record)
			elif _ron_story_has_passed():
				_repair_ron_authority_for_saved_step()


func _repair_ron_authority_for_saved_step() -> void:
	if _current_step in ["ron_approaches", "ron_greeting"]:
		_restart_ron_approach_from_physical_state({})
		return
	if _ron_story_has_passed():
		var now := float(_scheduler.get_current_tick())
		var completed := _baseline_ron_authority()
		completed["phase"] = RON_PHASE_COMPLETE
		completed["started_at"] = now
		completed["arrived_at"] = now
		completed["completed_at"] = now
		completed["endpoint"] = _authority_v3_data(_ron_approach_endpoint())
		_publish_sequence_authority_section("ron", completed)
		return
	_publish_sequence_authority_section("ron", _baseline_ron_authority())


func _restart_ron_approach_from_physical_state(prior: Dictionary) -> void:
	var now := float(_scheduler.get_current_tick())
	var record := _baseline_ron_authority()
	record["phase"] = RON_PHASE_APPROACHING
	record["started_at"] = now
	record["endpoint"] = _authority_v3_data(_ron_approach_endpoint())
	record["next_retry_tick"] = now
	if prior.get("operations", null) is Array:
		record["operations"] = (prior.get("operations", []) as Array).duplicate(true)
		record["operation_counter"] = int(prior.get(
			"operation_counter", (record["operations"] as Array).size()))
	if prior.get("interruptions", null) is Array:
		record["interruptions"] = (prior.get("interruptions", []) as Array).duplicate(true)
	_current_step = "ron_approaches"
	_player.set_move_enabled(false)
	_restore_ron_post_warp_presenter()
	_publish_sequence_authority_section("ron", record)
	_update_ron_approach_authority()


func _terminal_story_has_passed() -> bool:
	return _current_step in [
		"ron_drinks", "walk_to_drink", "drink", "ron_move_fast",
		"explore_workspace", "tag_notify", "walk_to_exit", "transition_out", "complete",
	]


func _restore_terminal_authority_after_snapshot() -> void:
	var record := _sequence_authority_section("terminal")
	if not _valid_terminal_authority(record):
		_repair_terminal_authority_for_saved_step()
		return
	var phase := str(record.get("phase", ""))
	match phase:
		TERMINAL_PHASE_ACTIVE:
			var mode := str(record.get("mode", ""))
			if mode == TERMINAL_MODE_TUTORIAL and _current_step != "terminal_focus":
				_repair_terminal_authority_for_saved_step()
				return
			if mode == TERMINAL_MODE_REREAD \
					and (_current_step == "terminal_focus" or not _terminal_story_has_passed() \
						and _current_step != "terminal_data"):
				_repair_terminal_authority_for_saved_step()
				return
			if mode == TERMINAL_MODE_TUTORIAL:
				_current_step = "terminal_focus"
			_set_aster_source_projection(_terminal, false)
			_apply_terminal_focus_presenter(record)
			_arm_terminal_authority(record)
		TERMINAL_PHASE_SETTLING:
			if _current_step != "terminal_data":
				_repair_terminal_authority_for_saved_step()
				return
			_end_terminal_screen_focus(record.get("return_camera", {}) as Dictionary)
			_player.set_move_enabled(bool(record.get("return_move_enabled", true)))
			_set_aster_source_projection(_terminal, false)
			_arm_terminal_authority(record)
		TERMINAL_PHASE_COMPLETE:
			if _current_step in ["terminal_focus", "terminal_data"]:
				_repair_terminal_authority_for_saved_step()
				return
			if _terminal_story_has_passed():
				_restore_terminal_idle_presenter(true)
			elif _current_step == "show_terminal":
				_publish_sequence_authority_section(
					"terminal", _baseline_terminal_authority())
				_restore_terminal_idle_presenter(true)
		TERMINAL_PHASE_IDLE:
			if _current_step in ["terminal_focus", "terminal_data"]:
				_repair_terminal_authority_for_saved_step()
			elif _terminal_story_has_passed():
				_repair_terminal_authority_for_saved_step()
			elif _current_step == "show_terminal":
				# An accepted-before-owner snapshot deliberately burns the old
				# monotonic edge above, but it must also retract that one-shot's
				# spent presenter/registry bit. Otherwise the save looks
				# actionable while GameState still rejects the required retry.
				_restore_terminal_idle_presenter(true)


func _repair_terminal_authority_for_saved_step() -> void:
	if _current_step == "terminal_focus":
		# The focus animation is not proof of a terminal read. A missing/edited
		# receipt returns to the exact physical source instead of granting focus.
		_current_step = "show_terminal"
		_player.set_move_enabled(true)
		var retry := _baseline_terminal_authority()
		retry["source_trigger_count"] = maxi(
			0, _aster_source_trigger_count(_terminal))
		_publish_sequence_authority_section("terminal", retry)
		_restore_terminal_idle_presenter(true)
		return
	if _current_step == "terminal_data":
		# Without the active/settling record there is no proof the screen was paid
		# for. Return to the readable terminal rather than granting an instant focus.
		_current_step = "show_terminal"
		_player.set_move_enabled(true)
		_restore_terminal_idle_presenter(true)
		var retry := _baseline_terminal_authority()
		retry["source_trigger_count"] = maxi(
			0, _aster_source_trigger_count(_terminal))
		_publish_sequence_authority_section("terminal", retry)
		return
	if _terminal_story_has_passed():
		var now := float(_scheduler.get_current_tick())
		var complete := _baseline_terminal_authority()
		complete["phase"] = TERMINAL_PHASE_COMPLETE
		complete["started_at"] = now
		complete["tutorial_complete"] = true
		complete["source_trigger_count"] = maxi(
			0, _aster_source_trigger_count(_terminal))
		_publish_sequence_authority_section("terminal", complete)
		_restore_terminal_idle_presenter(true)
		return
	var baseline := _baseline_terminal_authority()
	baseline["source_trigger_count"] = maxi(
		0, _aster_source_trigger_count(_terminal))
	_publish_sequence_authority_section("terminal", baseline)
	_restore_terminal_idle_presenter(_current_step == "show_terminal")


func _restore_terminal_idle_presenter(enabled: bool) -> void:
	if _terminal_focus_active:
		_end_terminal_screen_focus()
	if _terminal_screen_detail != null:
		_terminal_screen_detail.visible = false
	if _terminal_screen_lowfi != null:
		_terminal_screen_lowfi.visible = true
	_set_aster_source_projection(_terminal, enabled)


func _restore_transition_authority_after_snapshot() -> void:
	var record := _sequence_authority_section("transition")
	if not _valid_transition_authority(record):
		_repair_transition_authority_for_saved_step()
		return
	var phase := str(record.get("phase", ""))
	match phase:
		TRANSITION_PHASE_FADING:
			if _current_step != "transition_out":
				_repair_transition_authority_for_saved_step()
				return
			requested_scene_change = ""
			_apply_transition_presenter(record)
			_arm_transition_authority(record)
		TRANSITION_PHASE_COMPLETE:
			if _current_step == "transition_out":
				_complete()
			elif _current_step == "complete":
				_player.set_move_enabled(false)
				var camera_v: Variant = record.get("camera", null)
				if camera_v is Dictionary:
					_apply_authority_camera_state(camera_v as Dictionary)
				_fade_start_tick = float(record.get("started_at", _scheduler.get_current_tick()))
				_update_fades()
				# A crash can leave the transition autosave as the newest slot before
				# Godot swaps scenes. Re-applying the committed handoff is idempotent;
				# never strand a legitimate load on the fully black source scene.
				requested_scene_change = "res://scenes/tutorial/peris_sim.tscn"
				if not suppress_scene_change:
					call_deferred("_resume_completed_transition")
			else:
				_repair_transition_authority_for_saved_step()
		TRANSITION_PHASE_IDLE:
			if _current_step in ["transition_out", "complete"]:
				_repair_transition_authority_for_saved_step()


func _repair_transition_authority_for_saved_step() -> void:
	if _current_step in ["transition_out", "complete"]:
		requested_scene_change = ""
		# A missing or edited deadline cannot turn load into a scene skip. Rebuild
		# the complete fade from the restored physical/camera state.
		_current_step = "walk_to_exit"
		if _fade_rect != null:
			_fade_rect.color = Color(0.05, 0.03, 0.01, 0.0)
		_publish_sequence_authority_section("transition", _baseline_transition_authority())
		_start_transition_out()
		return
	_publish_sequence_authority_section("transition", _baseline_transition_authority())


func _resume_completed_transition() -> void:
	var record := _sequence_authority_section("transition")
	if not _valid_transition_authority(record) \
			or str(record.get("phase", "")) != TRANSITION_PHASE_COMPLETE:
		return
	get_tree().change_scene_to_file("res://scenes/tutorial/peris_sim.tscn")


func _restore_drink_machine_presenter(enabled: bool) -> void:
	if _drink_machine == null or not is_instance_valid(_drink_machine):
		return
	_set_aster_source_projection(_drink_machine, enabled)

func _start_ron_move_fast() -> void:
	_enter_step("ron_move_fast")
	var hallway_world := _grid.grid_to_world(HALLWAY_EXIT_CELL)
	if _ron and _ron.has_method("walk_to"):
		_ron.walk_to(_placement_or_position(
			"RonExitTarget",
			Vector3(hallway_world.x - 1.0, 0.0, hallway_world.z)
		))
	_dialogue_chain([
		"aster_sim.ron.move_fast",
		"aster_sim.ron.lighting",
		"aster_sim.aster.lighting",
		"aster_sim.ron.tag_day_jobs",
	], _start_explore_workspace)

func _start_explore_workspace() -> void:
	_enter_step("explore_workspace")
	# The room objects establish Aster through optional detail. The hallway itself is the
	# progression gate: attempting to leave advances to Tag Day without requiring a checklist.
	_reset_workspace_progress()
	_build_exploration_objects()
	_explore_gate_unlocked = false
	_explore_gate_fired = false
	if _tutorial_prompt != null and _tutorial_prompt.has_method("show_prompt"):
		_tutorial_prompt.show_prompt(
			"Look around Aster's workspace, then continue through the hallway when you're ready.",
			5.0
		)
	_unlock_exploration_gate()

func _unlock_exploration_gate() -> void:
	if _explore_gate_unlocked:
		return
	_explore_gate_unlocked = true

func _maybe_unlock_exploration_gate() -> void:
	# Optional room reads still report telemetry, but never gate the hallway.
	_unlock_exploration_gate()

func _reset_workspace_progress() -> void:
	_workspace_thread_counts.clear()
	for thread_id in WORKSPACE_THREAD_REQUIRED:
		_workspace_thread_counts[thread_id] = 0
	_workspace_zone_counts.clear()


func _register_workspace_zone(zone: Node, thread_id: String, contribution_limit: int) -> void:
	if zone == null or not zone.has_signal("interacted"):
		return
	var zone_id := str(zone.name)
	var callback := Callable(self, "_on_workspace_zone_interacted").bind(
		thread_id,
		zone_id,
		maxi(1, contribution_limit)
	)
	if not zone.is_connected("interacted", callback):
		zone.connect("interacted", callback)

func _on_workspace_zone_interacted(thread_id: String, zone_id: String, contribution_limit: int) -> void:
	if _current_step != "explore_workspace" or not WORKSPACE_THREAD_REQUIRED.has(thread_id):
		return
	var prior_zone_count := int(_workspace_zone_counts.get(zone_id, 0))
	if prior_zone_count >= contribution_limit:
		return
	_workspace_zone_counts[zone_id] = prior_zone_count + 1
	var required := int(WORKSPACE_THREAD_REQUIRED[thread_id])
	_workspace_thread_counts[thread_id] = mini(
		int(_workspace_thread_counts.get(thread_id, 0)) + 1,
		required
	)
	_maybe_unlock_exploration_gate()

func _workspace_completed_thread_count() -> int:
	var completed := 0
	for thread_id in WORKSPACE_THREAD_REQUIRED:
		if int(_workspace_thread_counts.get(thread_id, 0)) >= int(WORKSPACE_THREAD_REQUIRED[thread_id]):
			completed += 1
	return completed

func _workspace_review_complete() -> bool:
	return _workspace_completed_thread_count() == WORKSPACE_THREAD_REQUIRED.size()




func _on_exploration_gate_interacted() -> void:
	if not _explore_gate_unlocked or _explore_gate_fired:
		return
	_explore_gate_fired = true
	_start_tag_notify()

func _start_tag_notify() -> void:
	_enter_step("tag_notify")
	_dialogue_chain(
		["aster_sim.device.tag_verify", "aster_sim.ron.tag_notify"],
		_start_walk_to_exit
	)

func _start_walk_to_exit() -> void:
	_enter_step("walk_to_exit")
	_dialogue_chain(["aster_sim.tag_routine"], _start_transition_out)

func _start_transition_out() -> void:
	var existing := _sequence_authority_section("transition")
	if _valid_transition_authority(existing) \
			and str(existing.get("phase", "")) == TRANSITION_PHASE_FADING:
		_apply_transition_presenter(existing)
		_arm_transition_authority(existing)
		return
	_enter_step("transition_out")
	var now := float(_scheduler.get_current_tick())
	var record := _baseline_transition_authority()
	record["phase"] = TRANSITION_PHASE_FADING
	record["started_at"] = now
	record["deadline"] = now + TRANSITION_DURATION
	record["camera"] = _capture_authority_camera_state()
	record["move_enabled_before"] = (
		bool(_player.is_move_enabled()) if _player != null \
			and _player.has_method("is_move_enabled") else true
	)
	requested_scene_change = ""
	_publish_sequence_authority_section("transition", record)
	_apply_transition_presenter(record)
	_arm_transition_authority(record)


func _apply_transition_presenter(record: Dictionary) -> void:
	_current_step = "transition_out"
	if _player != null:
		_player.set_move_enabled(false)
	var camera_v: Variant = record.get("camera", null)
	if camera_v is Dictionary and _valid_authority_camera_state(camera_v):
		_apply_authority_camera_state(camera_v as Dictionary)
	_fade_start_tick = float(record.get("started_at", _scheduler.get_current_tick()))
	_update_fades()


func _arm_transition_authority(record: Dictionary) -> void:
	if _scheduler == null:
		return
	_scheduler.cancel_tag(TRANSITION_AUTHORITY_TAG)
	_scheduler.cancel_tag("complete")
	if not _valid_transition_authority(record) \
			or str(record.get("phase", "")) != TRANSITION_PHASE_FADING:
		return
	var deadline := float(record.get("deadline", -1.0))
	var now := float(_scheduler.get_current_tick())
	if deadline <= now:
		_on_transition_authority_deadline(deadline)
	else:
		_scheduler.schedule_at(
			deadline,
			_on_transition_authority_deadline.bind(deadline),
			TRANSITION_AUTHORITY_TAG
		)


func _on_transition_authority_deadline(expected_deadline: float) -> void:
	var record := _sequence_authority_section("transition")
	if not _valid_transition_authority(record) \
			or str(record.get("phase", "")) != TRANSITION_PHASE_FADING \
			or not is_equal_approx(float(record.get("deadline", -1.0)), expected_deadline):
		return
	record["phase"] = TRANSITION_PHASE_COMPLETE
	record["completed_at"] = maxf(float(_scheduler.get_current_tick()), expected_deadline)
	_publish_sequence_authority_section("transition", record)
	_complete()

func _complete() -> void:
	var record := _sequence_authority_section("transition")
	if not _valid_transition_authority(record) \
			or str(record.get("phase", "")) != TRANSITION_PHASE_COMPLETE:
		return
	_enter_step("complete")
	_change_scene_or_record("res://scenes/tutorial/peris_sim.tscn")

# --- Environment ---

func _build_environment() -> void:
	# Load grid from level data
	_grid = GridWorld.new()
	_grid.load_from_json("res://data/levels/aster_sim.json")
	# The scene's ONE declaration of its modeled room: floor surface (overlays/raycast ride it),
	# grid seams aligned to the floor tiles, furniture occupancy, and the re-export guards.
	_room_binder.setup(self, _grid, {
		"root_name": "AsterRoom",
		"floor_surface_y": 0.063,  # the Room model's real floor TOP (measured) — characters/overlays ride it
		"grid_origin_xz": Vector2(-0.5, -0.42),
		"occupants": ["Desk", "drink_machine"],
		"gltf_path": "res://resources/models/aster-sim/room/aster-sim-room-hi-res.gltf",
		"wired_materials": ["aster-sim-room-hi-res_1", "aster-sim-room-hi-res_8"],
		"wired_normal_materials": ["aster-sim-room-hi-res_1"],
	})

	# Grid renderer creates floor collision and tile meshes.
	_renderer = GridRenderer.new()
	_renderer.name = "Environment"
	var warm_colors := {
		GridWorld.Tile.FLOOR: Color(0.12, 0.1, 0.08),
		GridWorld.Tile.WALL: Color(0.15, 0.12, 0.1),
		GridWorld.Tile.FLORA: Color(0.1, 0.18, 0.1),
		GridWorld.Tile.IRON_BLOOM: Color(0.25, 0.1, 0.05),
		GridWorld.Tile.SHELTER: Color(0.1, 0.12, 0.2),
		GridWorld.Tile.TERMINAL: Color(0.1, 0.15, 0.18),
		GridWorld.Tile.FOOD: Color(0.1, 0.16, 0.1),
	}
	_renderer.setup(_grid, {"colors": warm_colors})
	add_child(_renderer)
	_apply_graybox_visibility()

	var env_node := _renderer
	var use_imported_room_lighting := show_high_res_room and not show_graybox_room

	# Drink machine.
	var drink_cells := _grid.find_tiles(GridWorld.Tile.FOOD)
	if not drink_cells.is_empty():
		var drink_world := _placement_or_grid("DrinkMachineAnchor", drink_cells[0], 0.0)
		_add_drink_machine_visual(env_node, drink_world)

	if not use_imported_room_lighting:
		_ensure_directional_light(env_node)

		var desk_area := _placement_or_grid("DataMotesCenter", Vector2i(3, 4), 1.8)
		_ensure_omni_light(
			env_node,
			"DeskLight",
			_placement_or_position("DeskLight", Vector3(desk_area.x, 2.5, desk_area.z)),
			Color(0.9, 0.75, 0.5),
			2.0,
			6.0
		)

		_ensure_omni_light(
			env_node,
			"DataLight",
			_placement_or_position("DataLight", Vector3(desk_area.x, 2.0, desk_area.z)),
			Color(0.3, 0.6, 0.8),
			1.0,
			4.0
		)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK if use_imported_room_lighting else Color(0.06, 0.05, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK if use_imported_room_lighting else Color(0.4, 0.35, 0.28)
	env.ambient_light_energy = 0.0 if use_imported_room_lighting else 0.5
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.15
	we.environment = env
	env_node.add_child(we)

func _apply_graybox_visibility() -> void:
	if show_graybox_room:
		return
	# Hide EVERY graybox mesh, including ones nested under the floor's StaticBody — collision
	# stays live for click raycasts; only the visuals go.
	for child in _renderer.find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).visible = false

func _ensure_directional_light(parent: Node3D) -> DirectionalLight3D:
	var scene_light := _placement_node("WarmDirectionalLight") as DirectionalLight3D
	if scene_light != null:
		return scene_light
	var dir_light := DirectionalLight3D.new()
	dir_light.name = "WarmDirectionalLight"
	dir_light.rotation_degrees = Vector3(-45, 30, 0)
	dir_light.light_color = Color(0.95, 0.85, 0.7)
	dir_light.light_energy = 0.7
	dir_light.shadow_enabled = true
	parent.add_child(dir_light)
	return dir_light

func _ensure_omni_light(
		parent: Node3D,
		light_name: String,
		fallback_position: Vector3,
		light_color: Color,
		light_energy: float,
		omni_range: float
	) -> OmniLight3D:
	var scene_light := _placement_node(light_name) as OmniLight3D
	if scene_light != null:
		return scene_light
	var light := OmniLight3D.new()
	light.name = light_name
	light.position = _local_for_parent(parent, fallback_position)
	light.light_color = light_color
	light.light_energy = light_energy
	light.omni_range = omni_range
	parent.add_child(light)
	return light

func _add_desk(parent: Node3D, pos: Vector3) -> void:
	# With the real room model active, the MODEL's desk is the desk: skip the graybox boxes and wrap
	# the imported meshes in the outline target so hover/SHIFT light the actual furniture.
	if _use_room_model():
		var model_meshes := _room_model_meshes("Desk")
		if not model_meshes.is_empty():
			# Centre + size from the PLACED model, so the hover/proximity volume follows the furniture.
			# An unplaced (identity, origin-piled) desk keeps the graybox anchor for its volume.
			var ab := _room_object_aabb("Desk")
			var placed := _room_object_placed("Desk") and ab.size != Vector3.ZERO
			var center := ab.get_center() if placed else pos + Vector3(0.0, 0.75, -0.1)
			var size := (ab.size + Vector3(0.4, 0.4, 0.4)) if placed else Vector3(2.4, 1.2, 1.8)
			_create_graybox_outline_target(parent, "RoomTargetDesk", center, size, model_meshes, "desk", 1.45)
			return
	var meshes: Array = []
	# Desktop surface
	var desk := MeshInstance3D.new()
	var db := BoxMesh.new()
	db.size = Vector3(2.0, 0.08, 1.0)
	desk.mesh = db
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.18, 0.14, 0.1)
	dm.roughness = 0.3
	desk.material_override = dm
	desk.position = pos + Vector3(0, 0.75, 0)
	parent.add_child(desk)
	meshes.append(desk)

	for x in [-0.8, 0.8]:
		for z in [-0.4, 0.4]:
			var leg := MeshInstance3D.new()
			var lb := BoxMesh.new()
			lb.size = Vector3(0.06, 0.75, 0.06)
			leg.mesh = lb
			leg.material_override = dm
			leg.position = pos + Vector3(x, 0.375, z)
			parent.add_child(leg)
			meshes.append(leg)

	# Chair.
	var chair := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.25
	cm.bottom_radius = 0.25
	cm.height = 0.08
	chair.mesh = cm
	var chair_mat := StandardMaterial3D.new()
	chair_mat.albedo_color = Color(0.2, 0.15, 0.12)
	chair.material_override = chair_mat
	chair.position = pos + Vector3(0, 0.5, -0.7)
	parent.add_child(chair)
	meshes.append(chair)

	_create_graybox_outline_target(parent, "RoomTargetDesk",
		pos + Vector3(0.0, 0.75, -0.1), Vector3(2.4, 1.2, 1.8), meshes, "desk", 1.45)

func _create_holo_display(pos: Vector3) -> MeshInstance3D:
	var display := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.8, 0.5, 0.02)
	display.mesh = pb
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.3, 0.4, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.15, 0.4, 0.55)
	mat.emission_energy_multiplier = 1.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	display.material_override = mat
	display.position = pos
	return display

func _add_drink_machine_visual(parent: Node3D, pos: Vector3) -> void:
	# The composed model carries the real drink machine: wrap ITS meshes, skip the graybox boxes.
	var prop := _model_prop(["drink_machine"])
	var meshes: Array = []
	if prop.is_empty():
		var body := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(0.8, 1.8, 0.6)
		body.mesh = bb
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.2, 0.18, 0.15)
		body.material_override = bm
		body.position = pos + Vector3(0, 0.9, 0)
		parent.add_child(body)
		meshes.append(body)

		var screen := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.5, 0.3, 0.02)
		screen.mesh = sb
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.2, 0.5, 0.3, 0.9)
		sm.emission_enabled = true
		sm.emission = Color(0.15, 0.4, 0.25)
		sm.emission_energy_multiplier = 1.0
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		screen.material_override = sm
		screen.position = pos + Vector3(0, 1.4, -0.32)
		parent.add_child(screen)
		meshes.append(screen)

		var lbl := Label3D.new()
		lbl.text = "DRINKS"
		lbl.font_size = 36
		lbl.pixel_size = 0.01
		lbl.modulate = Color(0.4, 0.7, 0.5, 0.7)
		lbl.position = pos + Vector3(0, 1.75, -0.32)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		parent.add_child(lbl)

	_create_graybox_outline_target(parent, "RoomTargetDrinkMachine",
		prop.center if not prop.is_empty() else pos + Vector3(0.0, 0.95, 0.0),
		prop.size if not prop.is_empty() else Vector3(1.2, 2.1, 1.0),
		prop.meshes if not prop.is_empty() else meshes, "drink_machine", 1.2)

# --- Terminal Interactable ---

func _build_terminal() -> void:
	var term_cells := _grid.find_tiles(GridWorld.Tile.TERMINAL)
	var term_pos := Vector3(3, 0, 0)
	if not term_cells.is_empty():
		term_pos = _placement_or_grid("TerminalAnchor", term_cells[0], 0.0)
	# The terminal lives ON the desk: with the room model active it follows the placed desk.
	term_pos = _model_or_marker("Desk", "TerminalAnchor", term_pos)

	if not Engine.is_editor_hint():
		_terminal = preload("res://scenes/game/interactable.tscn").instantiate()
		_terminal.name = "Terminal"
		_terminal.description = "Forecasting Terminal"
		_terminal.apply_interactable_spec("aster.terminal")
		_terminal.position = _local_for_parent(self, _placement_or_position("TerminalInteract", term_pos + Vector3(0, 0.8, 0)))
		add_child(_terminal)
		_terminal.interacted.connect(_on_terminal_interacted)

	var env_node: Node = find_child("Environment", false, false)
	if env_node:
		_add_desk(env_node, term_pos)
		_set_room_target_interaction_delegate(find_child("RoomTargetDesk", true, false), _terminal)
		_terminal_screen_world = term_pos + Vector3(0, 1.5, 0)
		var display := _create_holo_display(_terminal_screen_world)
		env_node.add_child(display)
		_data_displays.append(display)
		_terminal_screen_lowfi = display
		_terminal_screen_detail = _create_terminal_screen_detail(_terminal_screen_world)
		env_node.add_child(_terminal_screen_detail)
		# Face both screens the way the modeled monitor does — toward the chair, not the default +Z.
		var screen_yaw := atan2(_screen_facing().x, _screen_facing().z)
		display.rotation.y = screen_yaw
		_terminal_screen_detail.rotation.y = screen_yaw

## The detailed screen shown while the terminal is in focus. Placeholder art:
## a brighter framed panel plus a forecast readout, swapped in for the low-fi
## holo display when the player checks the terminal.
func _create_terminal_screen_detail(world_pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "TerminalScreenDetail"
	root.position = world_pos
	root.visible = false

	var panel := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.7, 1.05)
	panel.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.04, 0.10, 0.14)
	mat.emission_enabled = true
	mat.emission = Color(0.12, 0.34, 0.5)
	mat.emission_energy_multiplier = 1.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# A real, fixed screen facing +Z (the side Aster reads it from); the focus camera frames it head-on
	# from that front, so there's no need to billboard it (a swivelling screen reads as fake).
	panel.material_override = mat
	root.add_child(panel)

	var readout := Label3D.new()
	readout.no_depth_test = true
	# Aster's monitor message thread, from the GDD's opening of his workspace: the system credits Aster
	# for work the support crew actually did and rewards him with a drink-machine upgrade; Aster deflects
	# the credit; the system insists he did it all. This sets up the drink-machine ATP beat (the mugs on
	# his shelf are these rewards, accumulated). Characterisation in subtext — no narration needed.
	readout.text = "SYSTEM: Congrats on your hard work, task NVU-MAINT-0734-NORM. Your reward is an upgrade to your drink machine!\n\nASTER: You should thank the support crew. They did most of it.\n\nSYSTEM: But you did all the hard work!"
	readout.font_size = 22
	readout.pixel_size = 0.0030
	readout.width = 540  # wrap boundary (px) so the long crew line folds inside the panel
	readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	readout.modulate = Color(0.6, 0.85, 1.0)
	readout.outline_modulate = Color(0, 0, 0, 0.6)
	readout.outline_size = 6
	readout.position = Vector3(0, 0, 0.02)
	root.add_child(readout)
	_terminal_screen_readout = readout
	return root

# --- Drink Machine Interactable ---

func _build_drink_machine() -> void:
	var drink_cells := _grid.find_tiles(GridWorld.Tile.FOOD)
	var machine_pos := Vector3(8, 0, -3)
	if not drink_cells.is_empty():
		machine_pos = _placement_or_grid("DrinkMachineAnchor", drink_cells[0], 0.0)
	machine_pos = _model_or_marker("drink_machine", "DrinkMachineAnchor", machine_pos)

	if not Engine.is_editor_hint():
		_drink_machine = preload("res://scenes/game/interactable.tscn").instantiate()
		_drink_machine.name = "DrinkMachine"
		_drink_machine.description = "Drink Machine"
		_drink_machine.apply_interactable_spec("aster.drink_machine")
		_drink_machine.position = _local_for_parent(self, _placement_or_position("DrinkMachineInteract", machine_pos + Vector3(0, 0.9, 0)))
		# The proximity sphere stays centered on the machine face, but a click must stop Aster at the
		# measured floor point in front of it. Aster is displayed/collided at 2x scale, so using the
		# interaction sphere's centre as the destination embeds half of his capsule in the cabinet.
		var approach_position := _placement_or_position(
			"DrinkMachineApproach",
			Vector3(machine_pos.x, _grid.origin.y, machine_pos.z + 1.5)
		)
		_drink_machine.set_meta("interaction_target_position", approach_position)
		add_child(_drink_machine)
		_drink_machine.interacted.connect(_on_drink_interacted)
		var room_target := find_child("RoomTargetDrinkMachine", true, false)
		if room_target != null:
			# The modeled surface target and the Area3D are both click-pickable. Give both paths the
			# same destination so clicking either cannot regress to the cabinet centre.
			room_target.set_meta("interaction_target_position", approach_position)
		_set_room_target_interaction_delegate(room_target, _drink_machine)

# --- Exploration objects (post-drink, pre-Tag-Day) ---

func _build_exploration_objects() -> void:
	if Engine.is_editor_hint():
		return
	var env: Node3D = self
	if _renderer != null:
		env = _renderer
	_build_glass_bead_game(env)
	_build_painting_panel(env, Vector2i(6, 1), Vector2i(6, 3), "macabre_teal",
		Color(0.15, 0.38, 0.42), "aster.sim_expand.painting_1.line")
	_build_painting_panel(env, Vector2i(11, 1), Vector2i(11, 3), "hunter_ash",
		Color(0.4, 0.3, 0.18), "aster.sim_expand.painting_2.line")
	_build_awards_shelf(env)
	_build_jstore_shelf(env)
	_build_hallway_exit(env)


func _build_glass_bead_game(parent: Node3D) -> void:
	var bead_cell := Vector2i(7, 5)
	var world := _placement_or_grid("GlassBeadAnchor", bead_cell, 0.0)
	# The STANDALONE animated bead game (idle animation, bead connectors, glow) is the real prop:
	# instantiate it where the room model's embedded copy sits (or the marker), HIDE the embedded
	# static copy so they don't double-render, and wrap the animated meshes for hover/highlight.
	var embedded := _model_prop(["glass_bead_game"])
	var game := GLASS_BEAD_SCENE.instantiate() as Node3D
	if game != null:
		var spot := world
		if not embedded.is_empty():
			var c: Vector3 = embedded.center
			var s: Vector3 = embedded.size
			spot = Vector3(c.x, c.y - s.y * 0.5, c.z)
			for m in embedded.meshes:
				(m as MeshInstance3D).visible = false
		add_child(game)
		game.global_position = spot
		# The display script drives materials, connector lines, and the idle loop.
		var game_meshes: Array = game.find_children("*", "MeshInstance3D", true, false)
		var game_target := _create_graybox_outline_target(parent, "RoomTargetGlassBeadGame",
			spot + Vector3(0.0, 0.75, 0.0), Vector3(1.4, 1.4, 1.4), game_meshes, "glass_bead_game", 1.0)
		var game_zone := _make_exploration_zone(
			parent, _local_for_parent(parent, _placement_or_position("GlassBeadZoneMarker", world)),
			"GlassBeadZone", "aster.sim_expand.glass_bead.line", 1.4, 0.6)
		_set_room_target_interaction_delegate(game_target, game_zone)
		_register_workspace_zone(game_zone, "glass", 1)
		return
	var meshes: Array = []
	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.35
	bm.bottom_radius = 0.4
	bm.height = 0.12
	base.mesh = bm
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.08, 0.08, 0.12)
	base_mat.metallic = 0.5
	base_mat.roughness = 0.3
	base_mat.emission_enabled = true
	base_mat.emission = Color(0.15, 0.2, 0.35)
	base_mat.emission_energy_multiplier = 0.4
	base.material_override = base_mat
	base.position = world + Vector3(0, 0.55, 0)
	parent.add_child(base)
	meshes.append(base)
	for i in range(8):
		var bead := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.05
		sm.height = 0.1
		bead.mesh = sm
		var bead_mat := StandardMaterial3D.new()
		bead_mat.albedo_color = Color(0.85, 0.9, 1.0, 0.8)
		bead_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bead_mat.emission_enabled = true
		bead_mat.emission = Color(0.5, 0.7, 1.0)
		bead_mat.emission_energy_multiplier = 1.2
		bead_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bead.material_override = bead_mat
		var angle := i * TAU / 8.0
		bead.position = world + Vector3(cos(angle) * 0.25, 0.9 + sin(angle * 2.0) * 0.08, sin(angle) * 0.25)
		parent.add_child(bead)
		meshes.append(bead)
	var target := _create_graybox_outline_target(parent, "RoomTargetGlassBeadGame",
		world + Vector3(0.0, 0.75, 0.0), Vector3(1.2, 1.1, 1.2), meshes, "glass_bead_game", 1.0)
	var zone := _make_exploration_zone(
		parent, _local_for_parent(parent, _placement_or_position("GlassBeadZoneMarker", world)),
		"GlassBeadZone",
		"aster.sim_expand.glass_bead.line",
		1.4, 0.6
	)
	_set_room_target_interaction_delegate(target, zone)
	_register_workspace_zone(zone, "glass", 1)

func _build_painting_panel(parent: Node3D, canvas_cell: Vector2i, zone_cell: Vector2i, zone_name: String, palette: Color, line_key: String) -> void:
	var marker_prefix := _exploration_marker_prefix(zone_name)
	var canvas_world := _placement_or_grid(marker_prefix + "Canvas", canvas_cell, 0.0)
	# Model painting (macabre_teal = "Painting 1", hunter_ash = "Painting 2"): wrap the real canvas.
	var model_name: String = "Painting 1" if zone_name == "macabre_teal" else "Painting 2"
	var prop := _model_prop([model_name])
	if not prop.is_empty():
		var model_target := _create_graybox_outline_target(parent, "RoomTarget%sPainting" % marker_prefix,
			prop.center, prop.size, prop.meshes, "%s_painting" % zone_name, 0.95)
		var model_zone_world := _placement_or_grid(marker_prefix + "ZoneMarker", zone_cell, 0.0)
		var model_zone := _make_exploration_sequence_zone(
			parent,
			_local_for_parent(parent, model_zone_world),
			zone_name + "Zone",
			[line_key, "aster.sim_expand.collection_community.line"],
			1.4,
			0.6
		)
		_set_room_target_interaction_delegate(model_target, model_zone)
		_register_workspace_zone(model_zone, "paintings", 2)
		return
	var panel := MeshInstance3D.new()
	var qb := BoxMesh.new()
	qb.size = Vector3(1.4, 1.0, 0.06)
	panel.mesh = qb
	var pm := StandardMaterial3D.new()
	pm.albedo_color = palette
	pm.roughness = 0.7
	panel.material_override = pm
	# Canvas frame.
	var frame := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(1.5, 1.1, 0.04)
	frame.mesh = fb
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.06, 0.06, 0.07)
	frame.material_override = fm
	panel.position = canvas_world + Vector3(0, 1.8, 0.02)
	frame.position = canvas_world + Vector3(0, 1.8, 0.0)
	parent.add_child(frame)
	parent.add_child(panel)
	var target_name := "RoomTarget%sPainting" % marker_prefix
	var target := _create_graybox_outline_target(parent, target_name,
		canvas_world + Vector3(0.0, 1.8, 0.03), Vector3(1.8, 1.35, 0.35), [frame, panel],
		"%s_painting" % zone_name, 0.95)
	var zone_world := _placement_or_grid(marker_prefix + "ZoneMarker", zone_cell, 0.0)
	var zone := _make_exploration_sequence_zone(
		parent,
		_local_for_parent(parent, zone_world),
		zone_name + "Zone",
		[line_key, "aster.sim_expand.collection_community.line"],
		1.4,
		0.6
	)
	_set_room_target_interaction_delegate(target, zone)
	_register_workspace_zone(zone, "paintings", 2)

func _build_awards_shelf(parent: Node3D) -> void:
	var shelf_cell := Vector2i(14, 2)
	var world := _placement_or_grid("AwardsShelf", shelf_cell, 0.0)
	# Model awards ("Award 1"/"Award 2"): wrap the real plaques.
	var prop := _model_prop(["Award 1", "Award 2"])
	if not prop.is_empty():
		var model_target := _create_graybox_outline_target(parent, "RoomTargetAwardsShelf",
			prop.center, prop.size, prop.meshes, "awards_shelf", 1.35)
		var model_center_zone := _make_exploration_sequence_zone(
			parent,
			_local_for_parent(parent, _placement_or_position("AwardsCenterZoneMarker", world + Vector3(0, 0, -0.4))),
			"AwardsCenterZone",
			["aster.sim_expand.awards.line", "aster.sim_expand.awards.journalism_line"],
			0.9,
			0.6
		)
		var model_journalism_zone := _make_exploration_zone(
			parent,
			_local_for_parent(parent, _placement_or_position("AwardsJournalismZoneMarker", world + Vector3(0, 0, 0.6))),
			"AwardsJournalismZone",
			"aster.sim_expand.awards.journalism_line",
			0.9,
			0.6
		)
		_set_room_target_interaction_delegate(model_target, model_center_zone)
		_register_workspace_zone(model_center_zone, "awards", 2)
		_register_workspace_zone(model_journalism_zone, "awards", 1)
		return
	var meshes: Array = []
	var shelf := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.25, 0.6, 2.0)
	shelf.mesh = sb
	var shelf_mat := StandardMaterial3D.new()
	shelf_mat.albedo_color = Color(0.15, 0.13, 0.1)
	shelf_mat.roughness = 0.4
	shelf.material_override = shelf_mat
	shelf.position = world + Vector3(0.6, 1.3, 0)
	parent.add_child(shelf)
	meshes.append(shelf)
	# Plaques.
	for i in range(6):
		var plaque := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.08, 0.22, 0.18)
		plaque.mesh = pb
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.55, 0.45, 0.18) if i % 2 == 0 else Color(0.65, 0.65, 0.68)
		pm.metallic = 0.6
		pm.roughness = 0.3
		plaque.material_override = pm
		plaque.position = world + Vector3(0.5, 1.35, -0.7 + i * 0.28)
		parent.add_child(plaque)
		meshes.append(plaque)
	var target := _create_graybox_outline_target(parent, "RoomTargetAwardsShelf",
		world + Vector3(0.55, 1.3, 0.0), Vector3(1.0, 1.2, 2.35), meshes, "awards_shelf", 1.35)
	# Two approach zones.
	var center_zone := _make_exploration_sequence_zone(
		parent,
		_local_for_parent(parent, _placement_or_position("AwardsCenterZoneMarker", world + Vector3(0, 0, -0.4))),
		"AwardsCenterZone",
		["aster.sim_expand.awards.line", "aster.sim_expand.awards.journalism_line"],
		0.9,
		0.6
	)
	var journalism_zone := _make_exploration_zone(
		parent,
		_local_for_parent(parent, _placement_or_position("AwardsJournalismZoneMarker", world + Vector3(0, 0, 0.6))),
		"AwardsJournalismZone",
		"aster.sim_expand.awards.journalism_line",
		0.9,
		0.6
	)
	_set_room_target_interaction_delegate(target, center_zone)
	_register_workspace_zone(center_zone, "awards", 2)
	_register_workspace_zone(journalism_zone, "awards", 1)

func _build_jstore_shelf(parent: Node3D) -> void:
	var shelf_cell := Vector2i(14, 5)
	var world := _placement_or_grid("JStoreShelf", shelf_cell, 0.0)
	# Model journals + mugs: wrap the real shelf contents, skip the graybox set.
	var prop := _model_prop(["j-store", "mug", "Shelf"])
	var meshes: Array = []
	if prop.is_empty():
		var shelf := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.25, 1.0, 2.0)
		shelf.mesh = sb
		var shelf_mat := StandardMaterial3D.new()
		shelf_mat.albedo_color = Color(0.15, 0.13, 0.1)
		shelf.material_override = shelf_mat
		shelf.position = world + Vector3(0.6, 1.1, 0)
		parent.add_child(shelf)
		meshes.append(shelf)
		# J-store spines.
		var spine_colors := [
			Color(0.15, 0.2, 0.35),
			Color(0.35, 0.18, 0.15),
			Color(0.18, 0.3, 0.2),
			Color(0.3, 0.25, 0.15),
			Color(0.2, 0.2, 0.3),
			Color(0.3, 0.2, 0.25),
		]
		for i in range(10):
			var spine := MeshInstance3D.new()
			var pb := BoxMesh.new()
			pb.size = Vector3(0.05, 0.4, 0.15)
			spine.mesh = pb
			var pm := StandardMaterial3D.new()
			pm.albedo_color = spine_colors[i % spine_colors.size()]
			spine.material_override = pm
			spine.position = world + Vector3(0.5, 0.9, -0.9 + i * 0.18)
			parent.add_child(spine)
			meshes.append(spine)
		# Empty mugs.
		for i in range(12):
			var mug := MeshInstance3D.new()
			var mb := CylinderMesh.new()
			mb.top_radius = 0.05
			mb.bottom_radius = 0.05
			mb.height = 0.1
			mug.mesh = mb
			var mm := StandardMaterial3D.new()
			mm.albedo_color = Color(0.25, 0.2, 0.18)
			mug.material_override = mm
			var row := i / 6
			var col := i % 6
			mug.position = world + Vector3(0.5, 1.7, -0.7 + col * 0.22 + row * 0.05)
			parent.add_child(mug)
			meshes.append(mug)
	var target := _create_graybox_outline_target(parent, "RoomTargetJStoreShelf",
		prop.center if not prop.is_empty() else world + Vector3(0.55, 1.15, 0.0),
		prop.size if not prop.is_empty() else Vector3(1.0, 1.8, 2.35),
		prop.meshes if not prop.is_empty() else meshes, "jstore_shelf", 1.45)
	var main_zone := _make_exploration_sequence_zone(parent, _local_for_parent(parent, _placement_or_position("JStoreMainZoneMarker", world + Vector3(0, 0, -0.4))),
		"JStoreMainZone",
		[
			"aster.sim_expand.bookshelf.line",
			"aster.sim_expand.bookshelf.articles_line",
		],
		0.9, 0.6)
	_set_room_target_interaction_delegate(target, main_zone)
	_register_workspace_zone(main_zone, "jstore", 2)

func _build_hallway_exit(parent: Node3D) -> void:
	var world := _placement_or_grid("HallwayExit", HALLWAY_EXIT_CELL, 0.0)
	# Archway frame.
	var arch := MeshInstance3D.new()
	var ab := BoxMesh.new()
	ab.size = Vector3(0.2, 2.8, 1.2)
	arch.mesh = ab
	var am := StandardMaterial3D.new()
	am.albedo_color = Color(0.12, 0.1, 0.08)
	arch.material_override = am
	arch.position = world + Vector3(0.6, 1.4, 0)
	parent.add_child(arch)
	_ensure_omni_light(
		parent,
		"HallwayExitLight",
		_placement_or_position("HallwayExitLight", world + Vector3(1.1, 1.8, 0)),
		Color(1.0, 0.85, 0.6),
		1.4,
		4.0
	)
	# Reuses Interactable plumbing for the timed gate.
	var gate := _create_interactable(parent, _local_for_parent(parent, world), "HallwayGate", 2.2, 0.8,
		"Continue", false, Interactable.InteractableType.HOLD_ACTION, "aster.hallway_gate")
	gate.connect("interacted", _on_exploration_gate_interacted)
	_explore_hallway_gate = gate

func _exploration_marker_prefix(zone_name: String) -> String:
	match zone_name:
		"macabre_teal":
			return "MacabreTeal"
		"hunter_ash":
			return "HunterAsh"
		_:
			return zone_name
