@tool
extends CharacterBody3D

const CHARACTER_INTERACTION_CONTROLLER := preload("res://scripts/game/characters/character_interaction_controller.gd")
const PLAYER_BODY_PRESENTER_GROUP := &"player_observation_party_presenters"
const PLAYER_BODY_PIXEL_OFFSETS: Array[Vector2] = [
	Vector2.ZERO,
	Vector2(0.0, -8.0), Vector2(0.0, 8.0),
	Vector2(-8.0, 0.0), Vector2(8.0, 0.0),
]

## Click-to-move character view. Prefer GameState; fallback moves locally.

@export var move_speed := 3.0
@export var run_speed := 6.0
@export var color := Color(0.29, 0.62, 1.0)  # Aster blue

## A free click whose target floor sits more than this far above/below the character's current
## level is rejected — they can't walk through the air to a different floor (which would just lerp
## the Y and "float between levels"). Flat scenes click same-Y floors, so this only bites where
## floors are stacked (the elevator); scripted moves bypass _set_click_target entirely.
const LEVEL_GAP := 1.6

## Overhead-deck pierce: on the warped helix the camera looks down THROUGH an upper coil onto the deck the
## character is on. A move click would otherwise land on that overhead coil (the destination ghost appears up
## there, the move walks the wrong way). So when zoomed IN, the ground raycast skips any hit sitting more than
## this far ABOVE the character and keeps casting to the deck below — UNLESS the camera is pulled back past
## ZOOM_OUT_FREE_DIST (zoomed out to read the structure / actually navigate an upper level), where the high hit
## is intended. The deck only climbs ~0.13/unit, so a near click never legitimately clears this; an upper coil
## sits a full turn (~9 units) above, well beyond it.
const CLIMB_HEIGHT_GATE := 3.0
const ZOOM_OUT_FREE_DIST := 24.0
## A move ray may pass through camera-occluded walls before it reaches the deck.
## Accept ordinary floors and authored ramps, but never treat a vertical wall or
## the underside of a structure as a movement surface.
const GROUND_NORMAL_MIN_DOT := 0.45
## Optional authoritative state.
var game_state: GameState
var char_id := ""  ## Character ID in GameState (e.g. "aster")

## Optional A* grid for a standalone Player that has no GameState. Once authoritative
## state is bound, its live grid is the single navigation source. Keeping the
## setter lets scene construction assign a grid before GameState is ready,
## without allowing that cached reference to diverge from GameState later.
var _standalone_grid_world: GridWorld
var grid_world: GridWorld:
	get:
		return game_state.grid if game_state != null else _standalone_grid_world
	set(value):
		_standalone_grid_world = value

var _target_pos: Vector3
var _moving := false
var _move_enabled := true
## "move" = a ground click moves the player; "select" = a ground click only
## emits ground_clicked for a sequence to interpret (e.g. "click the target").
var _click_mode := "move"
var _running := false
var _auto_path: Array[Vector3] = []
var _auto_path_index := 0
var _interaction_controller: CharacterInteractionController
var _pending_interaction_roots: Array[Node] = []
var _pending_interaction_targets: Array[Node] = []

var _ability_marker: MeshInstance3D
var _ability_marker_mat: StandardMaterial3D

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _label: Label3D = $Label3D
@onready var _damage_feedback_label: Label3D = get_node_or_null("DamageFeedbackLabel") as Label3D
var _damage_feedback_material_tween: Tween
var _damage_feedback_label_tween: Tween
## Presentation-only concealment remembers the body's prior authored visibility.
## GameState remains authoritative; this never changes collision, navigation,
## selection, or the character's logical presence.
var _concealment_presentation_hidden := false
var _concealment_mesh_visible_before := true
var _concealment_label_visible_before := true


# Hover grid: hovering the floor in move mode reveals a grid patch with the pointed-at cell lit, so
# you can see exactly where a click will move you. Cosmetic; follows the cursor, snapped to cells.
const HOVER_CELL := 1.0
const HOVER_SPAN := 5            # NxN grid patch shown around the hovered cell
const HOVER_TINT := Color(1.0, 1.0, 1.0)  # faded white — a quiet aim hint, not a character-coloured beacon
const HOVER_BOX_H := 0.6          # the Decal's downward projection DEPTH — kept TIGHT to the hovered deck so it
                                  # can't spill onto the helix loop stacked above/below (the "grid lands away
                                  # from where I pointed" bug); the box is centred ON the deck surface.
const HOVER_EMISSION_ENERGY := 0.6  # low: self-lit enough to read in a dark scene, under the glow bloom threshold
## Characters render on this dedicated VISUAL layer; the hover-grid Decal clears it from its cull_mask, so the
## grid stamps the FLOOR but passes THROUGH bodies (it never paints on a character standing in the patch).
## npc.gd / enemy.gd put their visual mesh on the same layer — keep these three in sync.
const NO_GRID_DECAL_LAYER := 2
var _hover_grid: Decal
var _last_ground_normal := Vector3.UP   # surface normal of the last ground raycast
## Typed identity of the exact accepted physics hit. Generated multi-level floors
## carry `navigation_level`; retaining it here prevents a warped inverse from
## flattening an upper-deck click onto level 0. This is command-local presentation
## state only and is never exposed through the player-observation policy surface.
var _last_ground_hit_result: Dictionary = {}

# Path preview: while hovering the floor in move mode, show (dim) the route a click WOULD take, before
# committing it. Recomputed only when the hovered cell changes (per-frame pathfinding would be wasteful).
const PREVIEW_COLOR := Color(0.55, 0.7, 0.85)  # muted blue-grey, distinct from the bright committed path
var _path_preview: PathRenderer
var _route_preview_presenter: Node
var _party_previews: Dictionary = {}   # char_id -> PathRenderer, one per member when group-moving
var _hover_last_mouse := Vector2(-1e9, -1e9)
# Queued PUSH mode (BG3-style): command-click a pushable queues it; hovering shows ghost previews of
# the character + object at the planned end state; command-click a reachable cell commits; the
# blocked cursor (X) marks destinations with no plan. Pure UI until the commit (one logged command).
const BLOCKED_CURSOR := preload("res://resources/cursors/cursor_blocked.svg")
var _push_obj_id := ""
var _push_plan: Dictionary = {}
var _push_plan_cell := Vector2i(0x7fffffff, 0x7fffffff)
var _push_ghost_char: MeshInstance3D
var _push_ghost_obj: MeshInstance3D
var _blocked_cursor_on := false
var _push_ghost_char_mat: StandardMaterial3D = null
var _push_ghost_obj_mat: StandardMaterial3D = null
var _push_ghost_red_mat: StandardMaterial3D = null
var _preview_last_cell := Vector2i(0x7fffffff, 0x7fffffff)
var _preview_last_level := -1
var _preview_last_graph_revision := -1
## The FLAT hovered move target while planning (Vector3.INF when not hovering). The scene's PathRenderManager
## reads this to draw a BG3-style destination ghost at the cursor BEFORE a move is committed.
var preview_move_target := Vector3.INF
## World-space command target that produced the currently displayed preview.
## A command consumes this exact endpoint instead of raycasting a second time
## through camera-occluded geometry and disagreeing with the visible route.
var _preview_commit_target := Vector3.INF
## Stable graph identity paired with `_preview_commit_target`. A stacked floor is part of the
## destination, never inferred again from an XZ-only cached endpoint at commit time.
var _preview_commit_location: Dictionary = {}
## A held rally owns every member's path/endpoint preview until it is committed or cancelled. Without
## this hand-off, each Player keeps running its ordinary cursor preview after SelectionController has
## assigned the formation: the active member writes the shared cursor cell over its resolved slot, while
## inactive members clear their slots because movement is disabled.
var _external_path_preview_active := false
var _hover_last_graph_revision := -1
## A stationary screen-space cursor still points at a different world location when the active
## camera moves or changes projection. Cache the camera sample with the cursor so the visible
## hover route always describes the command that a click at that pixel would issue.
var _hover_last_camera_instance_id := -1
var _hover_last_camera_transform := Transform3D.IDENTITY
var _hover_last_camera_projection := Projection()


signal arrived()
signal auto_path_complete()
## Emitted on every left-click that hits the ground, with the world position.
## Sequences listen to this instead of running their own ground raycast.
signal ground_clicked(world_pos: Vector3)
## UI-facing provenance for a command that could not become an authoritative move.
## The move APIs stay boolean/int contracts; preview and campaign hosts may surface
## this signal without inventing a second movement rule.
signal move_command_refused(char_id: String, reason: String)
signal push_queue_state_changed(active: bool)

var _last_move_refusal := ""

func _ready() -> void:
	_target_pos = global_position
	add_to_group(PLAYER_BODY_PRESENTER_GROUP)

	var capsule := CapsuleMesh.new()
	capsule.radius = 0.25
	capsule.height = 1.0
	_mesh.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color.darkened(0.5)
	mat.emission_energy_multiplier = 0.3
	_mesh.material_override = mat
	_mesh.layers = NO_GRID_DECAL_LAYER   # the hover-grid Decal skips this layer, so the grid passes through the body

	# The grounded-gait layer: the mesh faces travel, leans in, and step-bobs
	# from real displacement — the body itself stays a pure data mirror.
	if not Engine.is_editor_hint():
		add_child(LocomotionJuice.new())

	_build_hover_grid()

	# Path PREVIEW renderer: bound to no char (char_id "") so it draws ONLY its explicit path (the
	# would-be route), anchored to this player. Preview style = thin + DASHED in the character's own
	# colour — visually distinct from the solid committed ribbon the PathRenderManager draws.
	_path_preview = PathRenderer.new()
	_path_preview.preview_style = true
	add_child(_path_preview)
	_path_preview.setup(game_state, "", _character_color(), self)

	# The committed movement path is drawn by the scene's PathRenderManager (reusable, covers every
	# character), not a per-player line — so it shows for the party / NPCs / escorts too.
	_ability_marker = MeshInstance3D.new()
	var diamond := SphereMesh.new()
	diamond.radius = 0.2
	diamond.height = 0.4
	_ability_marker.mesh = diamond
	_ability_marker_mat = StandardMaterial3D.new()
	_ability_marker_mat.albedo_color = Color(0.9, 0.7, 0.2, 0.0)
	_ability_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ability_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ability_marker_mat.emission_enabled = true
	_ability_marker_mat.emission = Color(0.9, 0.6, 0.1)
	_ability_marker_mat.emission_energy_multiplier = 0.5
	_ability_marker.material_override = _ability_marker_mat
	_ability_marker.top_level = true
	add_child(_ability_marker)

	if Engine.is_editor_hint():
		return

	_interaction_controller = CHARACTER_INTERACTION_CONTROLLER.new()
	_interaction_controller.name = "CharacterInteractionController"
	add_child(_interaction_controller)
	_interaction_controller.setup(self)
	for root in _pending_interaction_roots:
		_interaction_controller.bind_interaction_root(root)
	for target in _pending_interaction_targets:
		_interaction_controller.bind_interaction_target(target)
	_pending_interaction_roots.clear()
	_pending_interaction_targets.clear()

	# Connect arrival signal if GameState is available
	if game_state:
		game_state.character_arrived.connect(_on_gs_arrived)
		if game_state.has_signal("knockdown_started"):
			game_state.knockdown_started.connect(_on_knockdown_started)
			game_state.knockdown_ended.connect(_on_knockdown_ended)


## Production-owned, render-backed body presentation for accessibility and
## automated player observation. The observer receives screen pixels, never
## private character/world transforms.
func get_player_observation_render_nodes() -> Array[Node3D]:
	var nodes: Array[Node3D] = []
	if _mesh != null and is_instance_valid(_mesh) and _mesh.is_visible_in_tree() \
			and _mesh.mesh != null and _mesh.transparency < 0.99:
		nodes.append(_mesh)
	return nodes


## FULL concealment tucks the visible body into the flora while the HUD renders
## the exact HIDDEN receipt. Restore the pre-existing authored visibility when
## concealment weakens or clears; never hide the CharacterBody3D itself.
func set_concealment_presentation_hidden(hidden: bool) -> void:
	if _mesh == null or not is_instance_valid(_mesh):
		return
	if hidden:
		if not _concealment_presentation_hidden:
			_concealment_mesh_visible_before = _mesh.visible
			_concealment_label_visible_before = (
				_label.visible if _label != null and is_instance_valid(_label) else false
			)
			_concealment_presentation_hidden = true
		# Reassert each sync so another presentation layer cannot accidentally
		# recreate the forbidden HIDDEN-plus-visible-body combination.
		_mesh.visible = false
		if _label != null and is_instance_valid(_label):
			_label.visible = false
		return
	if not _concealment_presentation_hidden:
		return
	_mesh.visible = _concealment_mesh_visible_before
	if _label != null and is_instance_valid(_label):
		_label.visible = _concealment_label_visible_before
	_concealment_presentation_hidden = false


func get_player_observation_portrait_key() -> String:
	return char_id


func get_player_observation_screen_candidates(
		camera: Camera3D, viewport: Viewport
	) -> Array[Vector2]:
	var candidates: Array[Vector2] = []
	if camera == null or viewport == null or not camera.is_inside_tree():
		return candidates
	var render_nodes := get_player_observation_render_nodes()
	if render_nodes.is_empty():
		return candidates
	var mesh_instance := render_nodes[0] as MeshInstance3D
	var visible_rect := viewport.get_visible_rect()
	var bounds := mesh_instance.get_aabb()
	var world_points: Array[Vector3] = [
		mesh_instance.global_transform * bounds.get_center(),
		mesh_instance.global_position,
	]
	for endpoint_index in range(8):
		world_points.append(
			mesh_instance.global_transform * bounds.get_endpoint(endpoint_index))
	for world_point in world_points:
		if camera.is_position_behind(world_point):
			continue
		var projected := camera.unproject_position(world_point)
		for offset in PLAYER_BODY_PIXEL_OFFSETS:
			var candidate := projected + offset
			if visible_rect.has_point(candidate) and not candidates.has(candidate):
				candidates.append(candidate)
	return candidates


## Explicit visual contract for DownedBodyManager. The character owns path-preview
## and ability-marker meshes as descendants too; a recursive mesh sweep would make
## those utilities part of the fallen body's hover outline and bounds.
func get_downed_outline_meshes() -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if _mesh != null and is_instance_valid(_mesh):
		meshes.append(_mesh)
	return meshes


## Present source-labelled damage on the character itself. The hidden Label3D is scene-authored so
## the first combat impact does not allocate and tree-enter UI in the middle of a scheduler callback.
## Encounter controllers remain responsible for authoritative HP and portrait state; this is view-only.
func show_damage_feedback(amount: float, source: String, flash_color: Color, hp_left: float) -> void:
	var feedback_started := PerformanceTrace.begin()
	if _mesh != null and _mesh.material_override is StandardMaterial3D:
		var mat := _mesh.material_override as StandardMaterial3D
		if _damage_feedback_material_tween != null and _damage_feedback_material_tween.is_valid():
			_damage_feedback_material_tween.kill()
		mat.albedo_color = flash_color
		_damage_feedback_material_tween = create_tween()
		_damage_feedback_material_tween.tween_property(mat, "albedo_color", color, 0.24)
	if _damage_feedback_label == null:
		PerformanceTrace.end(&"draw", &"player.damage_feedback", feedback_started, char_id, 0)
		return
	if _damage_feedback_label_tween != null and _damage_feedback_label_tween.is_valid():
		_damage_feedback_label_tween.kill()
	var start := global_position + Vector3(0.0, 2.25, 0.0)
	_damage_feedback_label.text = "%s  -%d HP  /  %d LEFT" % [
		source, int(round(amount)), int(ceil(hp_left))]
	_damage_feedback_label.global_position = start
	_damage_feedback_label.modulate = Color(flash_color, 1.0)
	_damage_feedback_label.visible = true
	_damage_feedback_label_tween = create_tween().set_parallel(true)
	_damage_feedback_label_tween.tween_property(
		_damage_feedback_label, "global_position", start + Vector3(0.0, 0.55, 0.0), 0.65)
	_damage_feedback_label_tween.tween_property(
		_damage_feedback_label, "modulate", Color(flash_color, 0.0), 0.65).set_delay(0.18)
	_damage_feedback_label_tween.chain().tween_callback(func():
		if is_instance_valid(_damage_feedback_label):
			_damage_feedback_label.visible = false
	)
	PerformanceTrace.end(&"draw", &"player.damage_feedback", feedback_started, char_id, 1)

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton

	# The `command` action (right mouse) is the RTS move command. Physics object picking can be dispatched
	# AFTER `_unhandled_input` (observed in Web exports), so viewport handled-state alone cannot prevent the
	# same click from moving the party before the object receives it. Preflight the command-target layer;
	# the target's input_event still owns and dispatches the actual interaction later in this input cycle.
	if mb.is_action_pressed("command"):
		if _screen_hits_command_target(mb.position):
			return
		_commit_short_ground_command(mb)
		return

	# `select` (left mouse) during a sequence's "click the world target" beat only reports the ground
	# position; the sequence interprets it. The SelectionController yields `select` to us here
	# (is_pick_mode). In normal "move" mode `select` belongs to the SelectionController (character pick).
	# While a push is queued: SHIFT-select commits at the crate's destination; plain select cancels.
	if mb.is_action_pressed("select") and _push_obj_id != "":
		_handle_queued_push_click(_raycast_ground(mb.position), _queue_modifier_held(mb))
		return

	if mb.is_action_pressed("select") and _click_mode == "select":
		var hit_sel := _raycast_ground(mb.position)
		if hit_sel != Vector3.INF:
			ground_clicked.emit(hit_sel)


## Capture the immutable production result of one classified human short-RMB
## release. SelectionController owns ordering; Player owns the exact visible
## collision/typed-ground query. No authority changes here.
func capture_short_command(
		screen_pos: Vector2, modifiers: Dictionary = {}
	) -> Dictionary:
	var command_hit := _raycast_command_target_hit(screen_pos)
	if not command_hit.is_empty():
		var target := command_hit.get("collider") as CollisionObject3D
		var event_position_v: Variant = command_hit.get("position", Vector3.INF)
		var event_position := event_position_v as Vector3 \
			if event_position_v is Vector3 else Vector3.INF
		return {
			"contract": "captured_short_command/v1",
			"kind": "surface",
			"target": target,
			"event_position": event_position,
			"screen_position": screen_pos,
			"modifiers": modifiers.duplicate(true),
		}
	var ground := _capture_short_ground_command(screen_pos)
	if not ground.is_empty():
		return {
			"contract": "captured_short_command/v1",
			"kind": "ground",
			"ground": ground,
			"screen_position": screen_pos,
			"modifiers": modifiers.duplicate(true),
		}
	return {
		"contract": "captured_short_command/v1",
		"kind": "refusal",
		"reason": "No walkable deck or command target at that point.",
		"screen_position": screen_pos,
		"modifiers": modifiers.duplicate(true),
	}


## Submit exactly one previously captured production record. A surface remains
## the semantic source of an interaction; a typed ground record enters the same
## movement commit used by ordinary physical input. Failure is always published
## through the player's visible refusal signal.
func submit_captured_short_command(command_record: Dictionary) -> bool:
	if str(command_record.get("contract", "")) != "captured_short_command/v1":
		present_move_refusal("COMMAND REFUSED // invalid pointer command record.")
		return false
	var kind := str(command_record.get("kind", ""))
	if kind == "surface":
		var target_v: Variant = command_record.get("target", null)
		var target := target_v as CollisionObject3D \
			if target_v is CollisionObject3D else null
		var event_position_v: Variant = command_record.get(
			"event_position", Vector3.INF)
		var event_position := event_position_v as Vector3 \
			if event_position_v is Vector3 else Vector3.INF
		if target != null and is_instance_valid(target) \
				and target.is_inside_tree() \
				and target.get_viewport() == get_viewport() \
				and target.has_method("submit_pointer_command") \
				and bool(target.call("submit_pointer_command", event_position)):
			return true
		present_move_refusal(
			"COMMAND REFUSED // the shown target is no longer available.")
		return false
	if kind == "ground":
		var ground_v: Variant = command_record.get("ground", {})
		if not (ground_v is Dictionary):
			present_move_refusal("No walkable deck at that point.")
			return false
		var screen_position_v: Variant = command_record.get(
			"screen_position", Vector2.ZERO)
		var screen_position := screen_position_v as Vector2 \
			if screen_position_v is Vector2 else Vector2.ZERO
		var modifiers_v: Variant = command_record.get("modifiers", {})
		var modifiers := modifiers_v as Dictionary \
			if modifiers_v is Dictionary else {}
		var command := _short_command_event(screen_position, modifiers)
		return _commit_captured_short_ground_command(
			command, (ground_v as Dictionary).duplicate(true))
	var reason := str(command_record.get(
		"reason", "No walkable deck at that point."))
	present_move_refusal(reason)
	return false


## Compatibility entry for callers that are already inside the production
## Player input path. SelectionController uses capture + FIFO submission above.
func submit_short_command(screen_pos: Vector2, modifiers: Dictionary = {}) -> bool:
	return submit_captured_short_command(
		capture_short_command(screen_pos, modifiers))


func _short_command_event(
		screen_pos: Vector2, modifiers: Dictionary
	) -> InputEventMouseButton:
	var command := InputEventMouseButton.new()
	command.button_index = MOUSE_BUTTON_RIGHT
	command.button_mask = MOUSE_BUTTON_MASK_RIGHT
	command.pressed = true
	command.position = screen_pos
	command.global_position = screen_pos
	command.alt_pressed = bool(modifiers.get("alt", false))
	command.shift_pressed = bool(modifiers.get("shift", false))
	command.ctrl_pressed = bool(modifiers.get("ctrl", false))
	command.meta_pressed = bool(modifiers.get("meta", false))
	return command


func _commit_short_ground_command(mb: InputEventMouseButton) -> bool:
	return _commit_captured_short_ground_command(
		mb, _capture_short_ground_command(mb.position))


func _capture_short_ground_command(screen_pos: Vector2) -> Dictionary:
	var cached_location: Dictionary = {}
	var captured_data_position := Vector3.INF
	var captured_grid_location_missing := false
	var cache_is_current := _preview_commit_target.is_finite() \
		and screen_pos.distance_to(_hover_last_mouse) <= 2.0 \
		and _preview_navigation_cache_is_current()
	var world_position := _preview_commit_target \
		if cache_is_current else Vector3.INF
	if cache_is_current:
		cached_location = _preview_commit_location.duplicate(true)
	if world_position == Vector3.INF:
		var ground_target := get_ground_navigation_target(screen_pos)
		var world_position_v: Variant = ground_target.get(
			"world_position", Vector3.INF)
		if world_position_v is Vector3:
			world_position = world_position_v as Vector3
		var navigation_location_v: Variant = ground_target.get(
			"navigation_location", {})
		if navigation_location_v is Dictionary:
			cached_location = (navigation_location_v as Dictionary).duplicate(true)
		var data_position_v: Variant = ground_target.get(
			"data_position", Vector3.INF)
		if data_position_v is Vector3:
			captured_data_position = data_position_v as Vector3
		captured_grid_location_missing = game_state != null \
			and grid_world != null \
			and ground_target.has("navigation_location") \
			and cached_location.is_empty()
	if not world_position.is_finite():
		return {}
	return {
		"world_position": world_position,
		"navigation_location": cached_location,
		"data_position": captured_data_position,
		"grid_location_missing": captured_grid_location_missing,
	}


func _commit_captured_short_ground_command(
		mb: InputEventMouseButton, ground_record: Dictionary
	) -> bool:
	if _push_obj_id != "":
		# SHIFT-click commits the queued push at the crate's destination; a plain click
		# abandons the queue and falls through to the ordinary move.
		if _queue_modifier_held(mb):
			var push_target_v: Variant = ground_record.get(
				"world_position", Vector3.INF)
			var push_target := push_target_v as Vector3 \
				if push_target_v is Vector3 else Vector3.INF
			_handle_queued_push_click(push_target, true)
			return true
		cancel_push_queue()
	if _click_mode != "move" or not _move_enabled:
		return false
	if _auto_path.size() > 0 and not (game_state and char_id != ""):
		return false  # Don't interrupt fallback auto-path with clicks
	var cached_location_v: Variant = ground_record.get(
		"navigation_location", {})
	var cached_location := cached_location_v as Dictionary \
		if cached_location_v is Dictionary else {}
	var captured_data_position_v: Variant = ground_record.get(
		"data_position", Vector3.INF)
	var captured_data_position := captured_data_position_v as Vector3 \
		if captured_data_position_v is Vector3 else Vector3.INF
	var captured_grid_location_missing := bool(ground_record.get(
		"grid_location_missing", false))
	var rhit_v: Variant = ground_record.get("world_position", Vector3.INF)
	var rhit := rhit_v as Vector3 if rhit_v is Vector3 else Vector3.INF
	if rhit != Vector3.INF:
		ground_clicked.emit(rhit)
		if captured_grid_location_missing:
			_refuse_move("No walkable deck at that point.")
			move_command_refused.emit(char_id, _last_move_refusal)
			return false
		var accepted := _set_click_target(
			rhit, true, cached_location, captured_data_position)
		if not accepted:
			move_command_refused.emit(char_id,
				_last_move_refusal if _last_move_refusal != "" else "No route to that deck.")
		return accepted
	else:
		move_command_refused.emit(char_id, "No walkable deck at that point.")
	return false

## Switch how a ground click is interpreted: "move" (default) or "select".
func set_click_mode(mode: String) -> void:
	_click_mode = mode if mode in ["move", "select"] else "move"

## True while a sequence beat wants the player to click a world TARGET (select-mode), not move.
## The SelectionController checks this to yield LEFT-click to player.gd's ground_clicked path.
func is_pick_mode() -> bool:
	return _click_mode != "move"

## True when the physics object picker will give this screen point to a live command target. This is a
## read-only preflight: do not mark the event handled here, because Interactable/OutlineSurfaceTarget/
## PushTarget must still receive the same event and emit its semantic request. Query every collision layer to
## mirror object-picking occlusion: a nearer pickable ground/character is not mistaken for a target behind it.
## Non-pickable wrappers are pierced exactly as the viewport picker pierces them.
func _screen_hits_command_target(screen_pos: Vector2) -> bool:
	return _raycast_command_target(screen_pos) != null


## Read-only description of what the shipped pointer would do at this exact pixel. Automated
## players use this presentation boundary instead of private node registries or authored world
## coordinates. The result deliberately exposes no node identity or world position: a policy can
## choose the same visible verb and screen point a person can, and nothing more.
func get_player_pointer_affordance(screen_pos: Vector2) -> Dictionary:
	var target := _raycast_command_target(screen_pos)
	if target != null:
		# The shipped outline manager resolves its collision wrapper to the same
		# interaction delegate before drawing the cursor verb. Mirror that exact
		# presentation seam here so observations never degrade a visible
		# "UPPER DECK > ARM NEXT MID" prompt into an invented generic INTERACT.
		if target.has_method("get_interaction_delegate"):
			var delegate_v: Variant = target.call("get_interaction_delegate")
			if delegate_v is CollisionObject3D and is_instance_valid(delegate_v):
				target = delegate_v as CollisionObject3D
		var verb := "INTERACT"
		var consequence := ""
		if target.has_method("get_action_verb"):
			verb = str(target.call("get_action_verb"))
		if target.has_method("get_action_preview"):
			consequence = str(target.call("get_action_preview"))
		return {
			"clickable": true,
			"kind": "interact",
			"verb": verb,
			"consequence": consequence,
		}
	var ground_hit := _raycast_ground(screen_pos)
	if ground_hit != Vector3.INF:
		var consequence := _route_consequence_for_hit(ground_hit)
		if consequence == "NO ROUTE":
			return {
				"clickable": false,
				"kind": "move",
				"verb": "MOVE",
				"consequence": consequence,
			}
		return {
			"clickable": true,
			"kind": "move",
			"verb": "MOVE",
			"consequence": consequence,
		}
	return {"clickable": false, "kind": "none", "verb": ""}


func _route_consequence_for_hit(ground_hit: Vector3) -> String:
	if game_state == null or char_id == "" or game_state.grid == null:
		return "WALK ROUTE"
	var data_hit := _ground_hit_to_data(ground_hit)
	var location := game_state.resolve_navigation_location(char_id, data_hit)
	if location.is_empty():
		return "NO ROUTE"
	var target_level := int(location.get(
		"level", game_state.get_character_level(char_id)))
	var route_consequence := "WALK ROUTE"
	if target_level == game_state.get_character_level(char_id):
		route_consequence = "WALK ROUTE"
	else:
		var preview := game_state.compute_preview_navigation(char_id, data_hit)
		if preview.is_empty() or (preview.get("path", []) as Array).size() < 2:
			return "NO ROUTE"
		route_consequence = "ROUTE TO CONNECTED DECK"
		var plan := preview.get("plan", {}) as Dictionary
		for edge_v in plan.get("edges", []):
			if not (edge_v is Dictionary):
				continue
			var edge_kind := str((edge_v as Dictionary).get(
				"kind", (edge_v as Dictionary).get("type", "traversal"))).to_upper()
			if edge_kind != "WALK":
				route_consequence = "ROUTE VIA %s" % edge_kind
				break
	var location_cell_v: Variant = location.get("cell", null)
	if location_cell_v is Vector2i \
			and game_state.grid.has_method("navigation_consequence"):
		var mechanism_consequence := str(game_state.grid.navigation_consequence(
			location_cell_v as Vector2i, target_level)).strip_edges()
		if not mechanism_consequence.is_empty():
			return "%s // %s" % [mechanism_consequence, route_consequence]
	return route_consequence


func _show_route_preview_annotation(screen_pos: Vector2, text: String) -> void:
	var presenter := _resolve_route_preview_presenter()
	if presenter == null:
		return
	if text.is_empty() or text == "NO ROUTE":
		presenter.call("clear_route_preview_annotation", self)
	else:
		presenter.call("present_route_preview_annotation", self, screen_pos, text)


func _resolve_route_preview_presenter() -> Node:
	if _route_preview_presenter != null and is_instance_valid(_route_preview_presenter):
		return _route_preview_presenter
	var ancestor: Node = self
	while ancestor != null:
		var candidate := ancestor.get_node_or_null("PathRenderManager")
		if candidate != null and candidate.has_method("present_route_preview_annotation") \
				and candidate.has_method("clear_route_preview_annotation"):
			_route_preview_presenter = candidate
			return candidate
		ancestor = ancestor.get_parent()
	return null


func _exit_tree() -> void:
	if _route_preview_presenter != null and is_instance_valid(_route_preview_presenter):
		_route_preview_presenter.call("clear_route_preview_annotation", self)
	_route_preview_presenter = null


func _raycast_command_target(screen_pos: Vector2) -> CollisionObject3D:
	var result := _raycast_command_target_hit(screen_pos)
	return result.get("collider") as CollisionObject3D \
		if not result.is_empty() else null


func _raycast_command_target_hit(screen_pos: Vector2) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var world := get_world_3d()
	if world == null:
		return {}
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var exclude: Array[RID] = []
	for _i in range(8):
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * 120.0)
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.exclude = exclude
		var result := world.direct_space_state.intersect_ray(query)
		if result.is_empty():
			return {}
		var collider := result.get("collider") as CollisionObject3D
		if collider == null:
			exclude.append(result["rid"])
			continue
		if not collider.input_ray_pickable:
			exclude.append(result["rid"])
			continue
		if collider.has_signal(&"interaction_requested") \
				or collider.has_signal(&"push_queue_requested"):
			return result.duplicate(true)
		return {}
	return {}


## Resolve a held-RMB Rally from the same visible collision surface used by a
## short interaction command.  A surface may publish a portable semantic
## formation region (for example the exact walkable vertices of a shelter); no
## Node identity crosses this seam.  Other surfaces retain ordinary typed-ground
## Rally behavior beneath the pointer.
func get_rally_navigation_target(screen_pos: Vector2) -> Dictionary:
	var command_hit := _raycast_command_target_hit(screen_pos)
	if not command_hit.is_empty():
		var target := command_hit.get("collider") as CollisionObject3D
		if target != null and target.has_method("get_interaction_delegate"):
			var delegate_v: Variant = target.call("get_interaction_delegate")
			if delegate_v is CollisionObject3D and is_instance_valid(delegate_v):
				target = delegate_v as CollisionObject3D
		if target != null:
			var region_v: Variant = null
			if target.has_method("get_rally_formation_region"):
				region_v = target.call("get_rally_formation_region")
			elif target.has_meta("rally_formation_region"):
				region_v = target.get_meta("rally_formation_region")
			if region_v is Dictionary and not (region_v as Dictionary).is_empty():
				return {
					"kind": "formation_region",
					"formation_region": (
						region_v as Dictionary).duplicate(true),
				}
	var ground := get_ground_navigation_target(screen_pos)
	if not ground.is_empty():
		ground["kind"] = "typed_ground"
	return ground

## The production pointer's typed ground result. SelectionController consumes the
## same record for Rally; callers that need only a world point use `_raycast_ground`.
## No node identity crosses this seam.
func get_ground_navigation_target(screen_pos: Vector2) -> Dictionary:
	var world_position := _raycast_ground(screen_pos)
	if not world_position.is_finite() or _last_ground_hit_result.is_empty():
		return {}
	var data_position := _ground_hit_to_data(world_position)
	if not data_position.is_finite():
		return {}
	var target := {
		"world_position": world_position,
		"normal": _last_ground_normal,
		"data_position": data_position,
	}
	if _last_ground_hit_result.has("navigation_level"):
		target["navigation_level"] = int(
			_last_ground_hit_result["navigation_level"])
	if game_state != null and char_id != "" and game_state.grid != null:
		target["navigation_location"] = game_state.resolve_navigation_location(
			char_id, data_position)
	return target


func _raycast_ground(screen_pos: Vector2) -> Vector3:
	_last_ground_hit_result.clear()
	var camera := get_viewport().get_camera_3d()
	if not camera:
		_last_ground_normal = Vector3.UP
		return Vector3.INF
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var space := get_world_3d().direct_space_state
	# Pierce overhead decks when zoomed in: skip a hit that sits well above the character (an upper helix coil)
	# and keep casting to the deck below, so the destination/ghost lands where the player is, not on the loop
	# overhead. Zoomed out far enough, take the first hit (reaching an upper level is then intended).
	var cam_dist := camera.global_position.distance_to(global_position)
	var exclude: Array[RID] = []
	for _i in range(6):   # pierce at most a few stacked coils
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
		query.collision_mask = 1  # Ground only
		query.exclude = exclude
		var result := space.intersect_ray(query)
		if result.is_empty():
			break
		var hitpos: Vector3 = result.position
		var hit_normal: Vector3 = result.get("normal", Vector3.UP)
		if _hit_height_ok(hitpos.y, global_position.y, cam_dist) and _hit_surface_ok(hit_normal):
			_last_ground_normal = hit_normal
			_last_ground_hit_result = {
				"world_position": hitpos,
				"normal": hit_normal,
			}
			var navigation_level := _ground_navigation_level(result.get("collider"))
			if navigation_level >= 0:
				_last_ground_hit_result["navigation_level"] = navigation_level
			return hitpos
		# Too high for this zoom, or not a walkable-facing surface (commonly a
		# camera-occluded wall): drop that collider and continue to the deck.
		exclude.append(result.get("rid"))
	_last_ground_normal = Vector3.UP
	return Vector3.INF


func _ground_navigation_level(collider_v: Variant) -> int:
	var collider := collider_v as Node
	while collider != null:
		if collider.has_meta("navigation_level"):
			var level := int(collider.get_meta("navigation_level", -1))
			if level >= 0 and (grid_world == null or level < grid_world.level_count):
				return level
			return -1
		collider = collider.get_parent()
	return -1


## Convert an accepted render-space ground point into authoritative flat data
## space. A matching typed hit removes its known floor lift before the warped
## inverse chooses a helix turn; an unrelated/direct world point falls back to
## the base-floor inverse.
func _ground_hit_to_data(world_hit: Vector3) -> Vector3:
	if not world_hit.is_finite() or game_state == null \
			or game_state.coord_map == null:
		return world_hit
	var navigation_level := -1
	var recorded_world_v: Variant = _last_ground_hit_result.get(
		"world_position", null)
	if recorded_world_v is Vector3 \
			and (recorded_world_v as Vector3).distance_to(world_hit) <= 0.002:
		navigation_level = int(_last_ground_hit_result.get(
			"navigation_level", -1))
	if navigation_level >= 0 and grid_world != null:
		var data_y := grid_world.grid_to_world(
			Vector2i.ZERO, navigation_level).y
		if game_state.coord_map.has_method("to_data_on_surface"):
			var typed_data_v: Variant = game_state.coord_map.call(
				"to_data_on_surface", world_hit, data_y)
			if typed_data_v is Vector3:
				return typed_data_v as Vector3
		var fallback_data_v: Variant = game_state.coord_map.call(
			"to_data", world_hit)
		if fallback_data_v is Vector3:
			var fallback_data := fallback_data_v as Vector3
			fallback_data.y = data_y
			return fallback_data
		return Vector3.INF
	var data_v: Variant = game_state.coord_map.call("to_data", world_hit)
	return data_v as Vector3 if data_v is Vector3 else Vector3.INF

## Whether a ground-ray hit at world height `hit_y` is an acceptable move target for a character standing at
## `char_y`, given the camera sits `cam_dist` from that character. Zoomed IN (camera close), a hit more than
## CLIMB_HEIGHT_GATE above the character is an overhead deck (an upper helix coil) and is rejected so the ray
## pierces to the deck below; zoomed OUT past ZOOM_OUT_FREE_DIST, any height is allowed (navigating the structure
## is then intended). Pure decision so it's unit-testable without a camera/physics scene.
func _hit_height_ok(hit_y: float, char_y: float, cam_dist: float) -> bool:
	return cam_dist > ZOOM_OUT_FREE_DIST or hit_y <= char_y + CLIMB_HEIGHT_GATE

func _hit_surface_ok(hit_normal: Vector3) -> bool:
	if not hit_normal.is_finite() or hit_normal.length_squared() < 0.0001:
		return false
	return hit_normal.normalized().dot(Vector3.UP) >= GROUND_NORMAL_MIN_DOT

# --- Hover grid (target preview) ---

func _build_hover_grid() -> void:
	# A Decal that projects the grid IMAGE straight DOWN onto whatever floor sits below the cursor, so it
	# CONFORMS to a curved/warped deck (the channels helix) instead of laying a flat quad that pokes through
	# it. The grid rides the Decal's EMISSION channel at low energy so it self-illuminates and reads in a dark
	# scene (the flure chamber) — a Decal's albedo is lit, so albedo alone would go dark there. The energy is
	# kept well under the glow bloom threshold so it stays crisp lines, never the solid glowing blob a hot
	# emission decal blooms into. Albedo carries the grid where there IS light; the texture's transparent gaps
	# project nothing, so only the coloured lines stamp onto the floor.
	_hover_grid = Decal.new()
	_hover_grid.top_level = true   # authored in world space; we set its global transform to the cell
	_hover_grid.visible = false
	var tex := _build_grid_texture()
	_hover_grid.texture_albedo = tex
	_hover_grid.texture_emission = tex
	_hover_grid.emission_energy = HOVER_EMISSION_ENERGY
	_hover_grid.albedo_mix = 1.0
	_hover_grid.modulate = Color(1, 1, 1, 1)   # the lines are already character-coloured inside the texture
	_hover_grid.size = Vector3(HOVER_SPAN * HOVER_CELL, HOVER_BOX_H, HOVER_SPAN * HOVER_CELL)
	_hover_grid.upper_fade = 0.2   # ease the projection on/off at the top and bottom of the box so the grid
	_hover_grid.lower_fade = 0.2   # fades onto the deck instead of cutting hard where the box ends
	# Project onto the floor only — clear the character visual layer so the grid passes THROUGH bodies/obstacles
	# tagged with it instead of painting on them.
	_hover_grid.cull_mask = _hover_grid.cull_mask & ~NO_GRID_DECAL_LAYER
	add_child(_hover_grid)

## Per-player grid IMAGE in the player's colour: grid LINES only (no filled centre cell), with a gentle
## radial dissolve so the full patch reads as a square but its corners soften instead of ending in a hard
## edge. The expensive pattern is computed ONCE (shared alpha), then tinted per colour.
static var _grid_alpha: PackedFloat32Array
static var _grid_dim := 0
static var _grid_texture_cache: Dictionary = {}

## 8x8 ordered (Bayer) dither matrix, 0..63. The grid's radial fade is rendered as a STIPPLE against these
## thresholds — the signature pixel-dither dissolve: solid lines at the centre breaking into sparser dots
## toward the rim, instead of a smooth alpha ramp. Density carries the fade, so it reads as pixel art.
const BAYER8 := [
	0, 32, 8, 40, 2, 34, 10, 42,
	48, 16, 56, 24, 50, 18, 58, 26,
	12, 44, 4, 36, 14, 46, 6, 38,
	60, 28, 52, 20, 62, 30, 54, 22,
	3, 35, 11, 43, 1, 33, 9, 41,
	51, 19, 59, 27, 49, 17, 57, 25,
	15, 47, 7, 39, 13, 45, 5, 37,
	63, 31, 55, 23, 61, 29, 53, 21,
]

static var _grid_rim_alpha: PackedFloat32Array

static func _ensure_grid_alpha() -> void:
	if _grid_dim != 0:
		return
	var cells := HOVER_SPAN
	var cpx := 40
	var dim := cells * cpx
	_grid_dim = dim
	var lw := 2
	var is_line: Array[bool] = []
	is_line.resize(dim)
	for c in range(cells + 1):
		var p: int = clampi(c * cpx, 0, dim - 1)
		for o in range(-lw, lw + 1):
			is_line[clampi(p + o, 0, dim - 1)] = true
	_grid_alpha = PackedFloat32Array()
	_grid_alpha.resize(dim * dim)
	var half := dim * 0.5
	for y in range(dim):
		var fy := (y + 0.5 - half) / half
		for x in range(dim):
			var fx := (x + 0.5 - half) / half
			# Per-line-pixel radial FADE (1 at the centre -> 0 past the rim). _build_grid_texture
			# dithers this into a stipple so the 5x5 visibly fades toward the edges.
			var r := sqrt(fx * fx + fy * fy)
			var fade := clampf((1.18 - r) / 0.68, 0.0, 1.0)
			_grid_alpha[y * dim + x] = fade if (is_line[x] or is_line[y]) else 0.0

	# Cache the dark 2px dilation once: the neighbourhood walk is colour-independent,
	# so rebuilding it per character colour would repeat the same work.
	_grid_rim_alpha = PackedFloat32Array()
	_grid_rim_alpha.resize(dim * dim)
	var rim_px := 2
	for y in range(dim):
		for x in range(dim):
			var fade := _grid_alpha[y * dim + x]
			if fade < 0.5:
				continue
			var rim_alpha := fade * 0.7
			for oy in range(-rim_px, rim_px + 1):
				for ox in range(-rim_px, rim_px + 1):
					var px := clampi(x + ox, 0, dim - 1)
					var py := clampi(y + oy, 0, dim - 1)
					var index := py * dim + px
					_grid_rim_alpha[index] = maxf(_grid_rim_alpha[index], rim_alpha)


func _build_grid_texture() -> ImageTexture:
	# CONTRAST is the whole game here: thin faded lines vanish against the room model's own white tile seams
	# (and inside character glow). Lines render in the CHARACTER's color over a dark cached rim. The radial
	# fade is the Bayer stipple, written into one byte buffer rather than per-pixel Image calls, and
	# completed color textures are shared between matching character instances/scenes.
	_ensure_grid_alpha()
	var dim := _grid_dim
	var tint := _character_color()
	var cache_key := tint.to_rgba32()
	if _grid_texture_cache.has(cache_key):
		return _grid_texture_cache[cache_key] as ImageTexture
	var line := Color(tint.r, tint.g, tint.b, 1.0).lightened(0.25)
	var rim := Color(0.03, 0.04, 0.05, 1.0)
	var line_r := int(round(clampf(line.r, 0.0, 1.0) * 255.0))
	var line_g := int(round(clampf(line.g, 0.0, 1.0) * 255.0))
	var line_b := int(round(clampf(line.b, 0.0, 1.0) * 255.0))
	var rim_r := int(round(rim.r * 255.0))
	var rim_g := int(round(rim.g * 255.0))
	var rim_b := int(round(rim.b * 255.0))
	var pixels := PackedByteArray()
	pixels.resize(dim * dim * 4)
	for y in range(dim):
		for x in range(dim):
			var index := y * dim + x
			var byte_index := index * 4
			var rim_alpha := _grid_rim_alpha[index]
			if rim_alpha > 0.0:
				pixels[byte_index] = rim_r
				pixels[byte_index + 1] = rim_g
				pixels[byte_index + 2] = rim_b
				pixels[byte_index + 3] = int(round(clampf(rim_alpha, 0.0, 1.0) * 255.0))
			var fade := _grid_alpha[index]
			if fade <= 0.0:
				continue
			var threshold: float = (float(BAYER8[(y & 7) * 8 + (x & 7)]) + 0.5) / 64.0
			if fade > threshold:
				pixels[byte_index] = line_r
				pixels[byte_index + 1] = line_g
				pixels[byte_index + 2] = line_b
				pixels[byte_index + 3] = 255
	var img := Image.create_from_data(dim, dim, false, Image.FORMAT_RGBA8, pixels)
	img.generate_mipmaps()
	var texture := ImageTexture.create_from_image(img)
	_grid_texture_cache[cache_key] = texture
	return texture
## Raycast the floor under the cursor and show the grid there. Only in move mode while move-enabled,
## so it doesn't appear during selection prompts or for non-active party members.
func _update_hover_from_screen(screen_pos: Vector2) -> void:
	if _hover_grid == null:
		return
	_show_route_preview_annotation(Vector2.ZERO, "")
	if _external_path_preview_active:
		_hover_grid.visible = false
		return
	if _click_mode != "move" or not _move_enabled:
		_hover_grid.visible = false
		_clear_path_preview()
		return
	var raycast_started := PerformanceTrace.begin()
	var hit := _raycast_ground(screen_pos)
	PerformanceTrace.end(&"update", &"player.hover_raycast", raycast_started, char_id, 1)
	if hit == Vector3.INF:
		_hover_grid.visible = false
		_clear_path_preview()
		if _push_obj_id != "":
			_set_blocked_cursor(true)  # off the floor entirely: no destination here
		return
	# Queued-push mode replaces the hover grid with the ghost preview (the BG3-style shadow of the
	# character + object at the planned end state), or the blocked cursor when there's no plan.
	if _push_obj_id != "":
		_hover_grid.visible = false
		_update_push_preview(hit)
		return
	# Drape the grid onto the surface under the cursor, then preview the path to it.
	var grid_started := PerformanceTrace.begin()
	_apply_hover_grid(hit, _last_ground_normal)
	PerformanceTrace.end(&"draw", &"player.hover_grid", grid_started, char_id, 1)
	_update_path_preview(hit)
	_show_route_preview_annotation(screen_pos, _route_consequence_for_hit(hit))

## Project the hover grid straight DOWN from above the hovered point. The Decal stamps its texture onto the
## floor inside its box, so it conforms to the curve below instead of laying a flat quad that clips. Cursor-
## free: the live cursor path and the data-layer simulate_hover_at() both route here. `normal` is ignored —
## a down-projecting Decal must NOT tilt to it (tilting reintroduces the clip).
func _apply_hover_grid(hit: Vector3, _normal: Vector3) -> void:
	if _hover_grid == null:
		return
	# Snap to the data-grid cell so the grid overlay lands on the SAME cells gameplay uses. On a warped scene
	# the snap happens in FLAT data space (world hit -> to_data -> snap to cell -> to_world back onto the deck),
	# so the Decal jumps cell-to-cell on the helix just like it does on a flat floor. Only X/Z matter — the
	# Decal supplies its own Y, projecting straight down from above the snapped point.
	var warped := game_state != null and game_state.coord_map != null
	var center: Vector3
	var basis := Basis.IDENTITY
	if warped:
		var flat_center: Vector3 = _hover_grid_center(_ground_hit_to_data(hit))
		center = game_state.coord_map.to_world(flat_center)
		# Turn the grid patch to the deck's local frame (a yaw-only basis: right = lane, forward = along the
		# path), so its lines sit on the warped cells' seams instead of the world axes. Projection stays
		# straight down — the warp basis keeps +Y up.
		basis = game_state.coord_map.to_basis(flat_center)
	else:
		center = _hover_grid_center(hit)
	# Centre the projection box ON the deck surface (not lifted above it), so its half-height reaches just
	# below and just above the floor — tight enough that a helix loop stacked overhead never falls inside the
	# box and gets the grid stamped on it too (that doubled stamp read as "the grid landed away from where I
	# pointed"). Guard the warped to_world's INF case.
	var origin := Vector3(center.x, center.y, center.z)
	if not origin.is_finite():
		_hover_grid.visible = false
		return
	_hover_grid.global_transform = Transform3D(basis, origin)
	_hover_grid.visible = true

## Drive the hover grid from a WORLD point with no cursor/camera — raycasts straight DOWN onto the floor
## collision and drapes the grid there. Lets the data layer (and headless tests) verify the hover overlay
## without simulating a mouse. Returns true if a surface was found under the point.
func simulate_hover_at(world_point: Vector3) -> bool:
	if _hover_grid == null:
		return false
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var q := PhysicsRayQueryParameters3D.create(world_point + Vector3(0, 3.0, 0), world_point - Vector3(0, 3.0, 0))
	q.collision_mask = 1
	var result := space.intersect_ray(q)
	if result.is_empty():
		_last_ground_hit_result.clear()
		_hover_grid.visible = false
		return false
	_last_ground_normal = result.get("normal", Vector3.UP)
	_last_ground_hit_result = {
		"world_position": result.position,
		"normal": _last_ground_normal,
	}
	var navigation_level := _ground_navigation_level(result.get("collider"))
	if navigation_level >= 0:
		_last_ground_hit_result["navigation_level"] = navigation_level
	_apply_hover_grid(result.position, result.get("normal", Vector3.UP))
	return true

## Snap a hovered floor point to the centre of the cell it falls in, so the hover overlay lands on the
## SAME cells gameplay uses (and the floor tiles they're aligned to). Routes through the game grid's
## own world<->cell mapping, which carries the grid's origin offset — a modeled room's seams sit on the
## floor tiles, not on the integer lattice. Returns the centre in world XZ, keeping the hit's Y for the
## caller to lift. Falls back to a unit lattice only when there's no grid (standalone preview).
func _hover_grid_center(hit: Vector3) -> Vector3:
	if game_state != null and game_state.grid != null:
		var level := game_state.grid.level_for_y(hit.y) \
			if game_state.grid.level_count > 1 \
			else (game_state.get_character_level(char_id) if char_id != "" else 0)
		var center: Vector3 = game_state.grid.grid_to_world(game_state.grid.world_to_grid(hit), level)
		return Vector3(center.x, hit.y, center.z)
	return Vector3(floorf(hit.x) + HOVER_CELL * 0.5, hit.y, floorf(hit.z) + HOVER_CELL * 0.5)

## Show the would-be route to the hovered point (dim), before a click commits it. Recomputed only when
## the hovered CELL changes — per-frame pathfinding for a cosmetic line would be wasteful. Cleared while
## actually moving (the committed path shows then) and when not hovering the floor. With a party selected
## (group_move) it previews EVERY member's path to its own spread destination, not just the active one.
func _current_navigation_graph_revision() -> int:
	return grid_world.get_path_walkability_revision() if grid_world != null else -1


func _preview_navigation_cache_is_current() -> bool:
	if _preview_commit_location.is_empty():
		# Some callers/tests seed only the world endpoint without a typed location. Commit still
		# resolves that full XYZ into a typed location before issuing a grid command.
		return _preview_commit_target.is_finite()
	if grid_world == null:
		return false
	return int(_preview_commit_location.get("graph_revision", -2)) \
		== _current_navigation_graph_revision()


func _update_path_preview(hit: Vector3) -> void:
	var perf_started := PerformanceTrace.begin()
	# SelectionController is displaying the exact per-member Rally formation. The ordinary hover
	# preview targets one shared cursor cell, so it must not compete for preview_move_target here.
	if _external_path_preview_active:
		PerformanceTrace.end(&"nav", &"player.path_preview", perf_started, "external", 0)
		return
	if _path_preview == null or game_state == null or char_id == "":
		if GridWorld._fx_debug:
			GridWorld._pf_trace("[preview] SKIP (path_preview=%s game_state=%s char_id='%s')" % [_path_preview != null, game_state != null, char_id])
		PerformanceTrace.end(&"nav", &"player.path_preview", perf_started, char_id, 0)
		return
	# Keep the preview ribbon on the LIVE game_state. _path_preview.setup() ran in _ready, BEFORE the host
	# assigns this player's game_state — so it captured null and never saw the coord_map, leaving the ribbon
	# FLAT on a warped scene (the channels helix) instead of riding the deck. Re-sync every frame (cheap).
	_path_preview.game_state = game_state
	if game_state.coord_map != null:
		hit = _ground_hit_to_data(hit)   # plan in the flat data frame; the ribbon warps back to the helix
	if game_state.is_moving(char_id):
		if GridWorld._fx_debug:
			GridWorld._pf_trace("[preview] clear — %s is MOVING (committed ribbon shows instead)" % char_id)
		_clear_path_preview()
		PerformanceTrace.end(&"nav", &"player.path_preview", perf_started, "moving", 0)
		return
	# Recompute only when the hovered DATA-grid identity changes. Level is part of that identity for
	# stacked nodes, and graph revision invalidates the cache when Basin topology changes beneath a
	# stationary cursor.
	var cell := game_state.grid.world_to_grid(hit) if game_state.grid != null else Vector2i(int(floorf(hit.x)), int(floorf(hit.z)))
	var hover_level := game_state.grid.level_for_y(hit.y) \
		if game_state.grid != null and game_state.grid.level_count > 1 \
		else game_state.get_character_level(char_id)
	var graph_revision := _current_navigation_graph_revision()
	if cell == _preview_last_cell and hover_level == _preview_last_level \
			and graph_revision == _preview_last_graph_revision:
		PerformanceTrace.end(&"nav", &"player.path_preview", perf_started, "cached", 0)
		return
	_preview_last_cell = cell
	_preview_last_level = hover_level
	_preview_last_graph_revision = graph_revision
	if group_move and game_state.get_party().size() > 1:
		_path_preview.clear_explicit_path()  # the per-member previews replace the single one
		_update_party_preview(hit)
		# Group commit consumes the same snapped anchor cell the party preview used.
		var group_target := hit
		if game_state.grid != null:
			group_target = game_state.grid.grid_to_world(
				game_state.grid.world_to_grid(hit), hover_level)
		_preview_commit_target = game_state.coord_map.to_world(group_target) \
			if game_state.coord_map != null else group_target
		_preview_commit_location = game_state.resolve_navigation_location(char_id, group_target) \
			if game_state.grid != null else {}
		PerformanceTrace.end(&"nav", &"player.path_preview", perf_started, "party", game_state.get_party().size())
		return
	_clear_party_preview()
	var preview := game_state.compute_preview_navigation(char_id, hit)
	var path: Array = preview.get("path", [])
	if GridWorld._fx_debug:
		GridWorld._pf_trace("[preview] hit=%s cell=%s char=%s -> compute_preview_path = %d pts: %s" % [str(hit), str(cell), char_id, path.size(), str(path)])
	if path.size() >= 2:
		_path_preview.set_explicit_path(path, 1)  # from_index 1: the renderer prepends the live start point
		var endpoint: Vector3 = path[path.size() - 1]
		preview_move_target = endpoint
		_preview_commit_target = game_state.coord_map.to_world(endpoint) \
			if game_state.coord_map != null else endpoint
		_preview_commit_location = (preview.get("location", {}) as Dictionary).duplicate(true)
	else:
		_path_preview.clear_explicit_path()
		preview_move_target = Vector3.INF
		_preview_commit_target = Vector3.INF
		_preview_commit_location.clear()
		if GridWorld._fx_debug:
			GridWorld._pf_trace("[preview] CLEARED — compute_preview_path returned < 2 points (no route to this cell)")
	# A raw, unroutable surface hit is not a truthful final position, so it does
	# not receive a destination ghost or become the cached command target.
	PerformanceTrace.end(&"nav", &"player.path_preview", perf_started, char_id, path.size())

## One dim ribbon per selected member, each in that member's colour, anchored to that member so it starts
## at them. Mirrors the party spread, so the preview matches the click.
func _update_party_preview(hit: Vector3) -> void:
	var perf_started := PerformanceTrace.begin()
	var entries: Array = game_state.compute_preview_party_paths(hit)
	var seen := {}
	for entry in entries:
		var cid: String = entry["char_id"]
		var path: Array = entry["path"]
		seen[cid] = true
		var pr: PathRenderer = _party_previews.get(cid)
		if pr == null:
			pr = PathRenderer.new()
			pr.preview_style = true
			add_child(pr)
			var node := _find_char_node(cid)
			var col := PREVIEW_COLOR
			if node != null and "color" in node:
				col = node.color
			pr.setup(game_state, "", col, node)  # anchor to the member so the ribbon starts at them
			_party_previews[cid] = pr
		if path.size() >= 2:
			_party_previews[cid].set_explicit_path(path, 1)
		else:
			_party_previews[cid].clear_explicit_path()
		# Ghost each member at its OWN spread destination (the manager reads preview_move_target on the node).
		var mnode := _find_char_node(cid)
		if mnode != null and "preview_move_target" in mnode:
			mnode.preview_move_target = path[path.size() - 1] if path.size() >= 1 else hit
	for cid in _party_previews.keys():
		if not seen.has(cid):
			_party_previews[cid].clear_explicit_path()
			var mnode := _find_char_node(cid)
			if mnode != null and "preview_move_target" in mnode:
				mnode.preview_move_target = Vector3.INF
	PerformanceTrace.end(&"nav", &"player.party_preview", perf_started, char_id, entries.size())

func _clear_party_preview() -> void:
	for cid in _party_previews.keys():
		_party_previews[cid].clear_explicit_path()
		var mnode := _find_char_node(cid)
		if mnode != null and "preview_move_target" in mnode:
			mnode.preview_move_target = Vector3.INF

## Enter queued-push mode for a pushable object (a click on its PushTarget got us here). The
## destination the player then SHIFT-clicks is the CRATE's target cell, never the pusher's.
func queue_push(obj_id: String) -> void:
	_push_obj_id = obj_id
	_push_plan = {}
	_push_plan_cell = Vector2i(0x7fffffff, 0x7fffffff)
	_hover_last_mouse = Vector2(-1e9, -1e9)  # force a preview refresh
	# Truly unpushable AS IS (boxed in — no one-step push exists in any direction): say so
	# immediately with the blocked cursor, before any destination is even hovered.
	_set_blocked_cursor(not _any_push_possible(obj_id))
	push_queue_state_changed.emit(true)

## Whether at least one adjacent one-cell push of this object is currently legal.
func _any_push_possible(obj_id: String) -> bool:
	if game_state == null or game_state.grid == null or char_id == "":
		return true
	var obj_cell: Vector2i = game_state.grid.world_to_grid(game_state.get_physics_position(obj_id))
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not game_state.plan_push_for(char_id, obj_id, obj_cell + d).is_empty():
			return true
	return false

func is_push_queued() -> bool:
	return _push_obj_id != ""

func cancel_push_queue() -> void:
	var was_queued := _push_obj_id != ""
	_push_obj_id = ""
	_push_plan = {}
	_set_blocked_cursor(false)
	_clear_push_ghosts()
	_clear_path_preview()
	if was_queued:
		push_queue_state_changed.emit(false)

## The SHIFT modifier on EVERY device: the raw keyboard modifier, or the `highlight` InputMap
## action held any other way — a gamepad shoulder button, or the touch cluster's latched SHIFT
## (which presses the same action). One modifier, one read, every input device.
func _queue_modifier_held(mb: InputEventMouseButton) -> bool:
	return mb.shift_pressed or Input.is_action_pressed("highlight")

## The one decision point for a click while a push is queued: SHIFT commits the crate to the
## clicked cell; anything else abandons the queue.
func _handle_queued_push_click(hit: Vector3, shift_held: bool) -> void:
	if shift_held and hit != Vector3.INF:
		_commit_push(hit)
		return
	cancel_push_queue()

## Hover while a push is queued: plan to the hovered cell; ghosts + the object's route when possible,
## the blocked (X) cursor when "there is not enough space".
func _update_push_preview(hit: Vector3) -> void:
	var perf_started := PerformanceTrace.begin()
	if game_state == null or game_state.grid == null or char_id == "":
		PerformanceTrace.end(&"nav", &"player.push_preview", perf_started, char_id, 0)
		return
	var cell: Vector2i = game_state.grid.world_to_grid(_ground_hit_to_data(hit))
	if cell == _push_plan_cell:
		PerformanceTrace.end(&"nav", &"player.push_preview", perf_started, "cached", 0)
		return
	_push_plan_cell = cell
	_push_plan = game_state.plan_push_for(char_id, _push_obj_id, cell)
	if _push_plan.is_empty():
		# Blocked destination: the X cursor AND the ghost pair in RED at the pointed cell —
		# the refusal is shown where the player is looking, not by the preview vanishing.
		_set_blocked_cursor(true)
		_clear_path_preview()
		_show_blocked_push_ghosts(cell)
		PerformanceTrace.end(&"nav", &"player.push_preview", perf_started, "blocked", 0)
		return
	_set_blocked_cursor(false)
	var steps: Array = _push_plan.get("steps", [])
	# The object's route, drawn with the dashed preview ribbon.
	var route: Array[Vector3] = [game_state.get_physics_position(_push_obj_id)]
	for step in steps:
		route.append(game_state.grid.grid_to_world(step["obj_to"], game_state.get_character_level(char_id)))
	if _path_preview != null and route.size() >= 2:
		_path_preview.set_explicit_path(route, 0)
	# Ghosts at the END state: the object on the target cell, the character on its final push cell.
	# The object ghost is the CRATE ITSELF, translucent — its real mesh, not a placeholder box.
	_ensure_push_ghosts()
	_push_ghost_obj.material_override = _push_ghost_obj_mat
	_push_ghost_char.material_override = _push_ghost_char_mat
	var src_mesh := _push_object_mesh(_push_obj_id)
	if src_mesh != null and _push_ghost_obj.mesh != src_mesh:
		_push_ghost_obj.mesh = src_mesh
	_push_ghost_obj.global_position = route[route.size() - 1] + Vector3(0, 0.45, 0)
	var char_end: Vector3 = game_state.grid.grid_to_world(
		(steps[steps.size() - 1] as Dictionary)["obj_from"] if not steps.is_empty() else game_state.grid.world_to_grid(global_position),
		game_state.get_character_level(char_id))
	_push_ghost_char.global_position = char_end + Vector3(0, 0.5, 0)
	_push_ghost_obj.visible = true
	_push_ghost_char.visible = true
	PerformanceTrace.end(&"nav", &"player.push_preview", perf_started, char_id, steps.size())

func _commit_push(hit: Vector3) -> void:
	if game_state == null or game_state.grid == null:
		cancel_push_queue()
		return
	var cell: Vector2i = game_state.grid.world_to_grid(_ground_hit_to_data(hit))
	if game_state.plan_push_for(char_id, _push_obj_id, cell).is_empty():
		return  # blocked destination: the operation does not occur (X cursor already shows why)
	game_state.command_push_object(char_id, _push_obj_id, cell)
	cancel_push_queue()

func _ensure_push_ghosts() -> void:
	if _push_ghost_char != null:
		return
	_push_ghost_char_mat = _ghost_material(_character_color())
	_push_ghost_obj_mat = _ghost_material(Color(0.8, 0.65, 0.4))
	_push_ghost_red_mat = _ghost_material(Color(0.9, 0.15, 0.12))
	_push_ghost_char = MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.25
	cap.height = 1.0
	_push_ghost_char.mesh = cap
	_push_ghost_char.material_override = _push_ghost_char_mat
	_push_ghost_char.top_level = true
	_push_ghost_char.visible = false
	add_child(_push_ghost_char)
	_push_ghost_obj = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.85, 0.9, 0.85)
	_push_ghost_obj.mesh = box
	_push_ghost_obj.material_override = _push_ghost_obj_mat
	_push_ghost_obj.top_level = true
	_push_ghost_obj.visible = false
	add_child(_push_ghost_obj)

## A blocked destination still SHOWS the plan the player asked for — the crate ghost on the
## pointed cell and the pusher capsule behind it along the naive push direction — both RED.
func _show_blocked_push_ghosts(cell: Vector2i) -> void:
	if game_state == null or game_state.grid == null:
		return
	_ensure_push_ghosts()
	var src_mesh := _push_object_mesh(_push_obj_id)
	if src_mesh != null and _push_ghost_obj.mesh != src_mesh:
		_push_ghost_obj.mesh = src_mesh
	_push_ghost_obj.material_override = _push_ghost_red_mat
	_push_ghost_char.material_override = _push_ghost_red_mat
	var level: int = game_state.get_character_level(char_id) if char_id != "" else 0
	var obj_cell: Vector2i = game_state.grid.world_to_grid(
		game_state.get_physics_position(_push_obj_id))
	var delta: Vector2i = cell - obj_cell
	var dir := Vector2i(signi(delta.x), 0) if absi(delta.x) >= absi(delta.y) \
		else Vector2i(0, signi(delta.y))
	if dir == Vector2i.ZERO:
		dir = Vector2i(1, 0)
	_push_ghost_obj.global_position = game_state.grid.grid_to_world(cell, level) + Vector3(0, 0.45, 0)
	_push_ghost_char.global_position = game_state.grid.grid_to_world(cell - dir, level) + Vector3(0, 0.5, 0)
	_push_ghost_obj.visible = true
	_push_ghost_char.visible = true

## The wrapped mesh of a pushable object, found via its PushTarget (group "push_targets").
## Null when no wrapper exists — the ghost keeps its default box.
func _push_object_mesh(target_obj_id: String) -> Mesh:
	if not is_inside_tree():
		return null
	for t in get_tree().get_nodes_in_group("push_targets"):
		if str(t.get("obj_id")) != target_obj_id:
			continue
		var wrapped := t.get_parent() as MeshInstance3D
		if wrapped != null and wrapped.mesh != null:
			return wrapped.mesh
	return null

func _ghost_material(tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(tint.r, tint.g, tint.b, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _clear_push_ghosts() -> void:
	if _push_ghost_char != null:
		_push_ghost_char.visible = false
	if _push_ghost_obj != null:
		_push_ghost_obj.visible = false

func _set_blocked_cursor(on: bool) -> void:
	if on == _blocked_cursor_on:
		return
	_blocked_cursor_on = on
	Input.set_custom_mouse_cursor(BLOCKED_CURSOR if on else null)

## The exhaustion fall (cosmetic only — the knockdown WINDOW is data-layer state): the body tips
## over when the failed dodge drops it and picks itself up when the window ends. Tweens never gate
## any transition; the data layer ends the knockdown on the scheduler regardless of the visual.
func _on_knockdown_started(id: String) -> void:
	if id != char_id or _mesh == null:
		return
	var tw := create_tween()  # @rendering_only
	tw.tween_property(_mesh, "rotation:x", PI * 0.45, 0.22).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_mesh, "position:y", _mesh.position.y - 0.25, 0.22).set_ease(Tween.EASE_OUT)

func _on_knockdown_ended(id: String) -> void:
	if id != char_id or _mesh == null:
		return
	var tw := create_tween()  # @rendering_only
	tw.tween_property(_mesh, "rotation:x", 0.0, 0.4).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(_mesh, "position:y", _mesh.position.y + 0.25, 0.4).set_ease(Tween.EASE_IN_OUT)

## The character's own colour for its preview ribbon (falls back to the muted preview grey).
func _character_color() -> Color:
	if "color" in self and self.color is Color:
		return self.color
	return PREVIEW_COLOR

func _clear_path_preview() -> void:
	if _path_preview != null:
		_path_preview.clear_explicit_path()
	_show_route_preview_annotation(Vector2.ZERO, "")
	_clear_party_preview()
	_preview_last_cell = Vector2i(0x7fffffff, 0x7fffffff)  # force a recompute on the next hover
	_preview_last_level = -1
	_preview_last_graph_revision = -1
	preview_move_target = Vector3.INF   # stop ghosting a destination once we're no longer planning one
	_preview_commit_target = Vector3.INF
	_preview_commit_location.clear()

## Temporarily hand ownership of this character's route and destination pill to a scene-level command
## preview (currently Rally). Enabling clears the old hover preview before the command assigns its exact
## endpoint; disabling only invalidates the hover cache so normal feedback resumes on the next frame.
func set_external_path_preview_active(active: bool) -> void:
	if _external_path_preview_active == active:
		return
	_external_path_preview_active = active
	if active:
		if _hover_grid != null:
			_hover_grid.visible = false
		_clear_path_preview()
	else:
		_hover_last_mouse = Vector2(-1e9, -1e9)
		_hover_last_camera_instance_id = -1

func is_external_path_preview_active() -> bool:
	return _external_path_preview_active

## The scene node for a character id (this player, or a sibling party member) — used to anchor each
## member's preview ribbon to that member and tint it their colour.
var _char_node_cache := {}

func _find_char_node(cid: String) -> Node3D:
	var cached = _char_node_cache.get(cid)
	if cached != null and is_instance_valid(cached):
		return cached
	var found := _find_char_node_uncached(cid)
	_char_node_cache[cid] = found
	return found

func _find_char_node_uncached(cid: String) -> Node3D:
	if cid == char_id:
		return self
	var root := get_parent()
	if root == null:
		return null
	for n in root.find_children("*", "", true, false):
		if n is Node3D and "char_id" in n and str(n.char_id) == cid:
			return n as Node3D
	return null

## When true, a ground click moves the whole party (spread onto distinct cells)
## via the data layer rather than just this character — so a multi-select group
## move never stacks members on one cell.
var group_move := false

func _refuse_move(reason: String) -> bool:
	_last_move_refusal = reason
	return false


## Public presentation seam for controllers whose ordinary routed command cannot reach its
## promised endpoint. A refused interaction must be as visible as a refused ground click.
func present_move_refusal(reason: String) -> void:
	_last_move_refusal = reason
	move_command_refused.emit(char_id, reason)

func _set_click_target(
		world_pos: Vector3,
		cancel_interaction := true,
		cached_navigation_location: Dictionary = {},
		captured_data_position := Vector3.INF
	) -> bool:
	_last_move_refusal = ""
	# A non-finite target (a ground ray that missed the floor returns Vector3.INF; a caller that didn't
	# pre-guard, e.g. the interaction walk-to) must NEVER enter movement: on a warped scene to_data() would
	# carry that infinity into world_to_grid + pathfinding and the path/grid drawing "goes to infinity".
	if not world_pos.is_finite():
		return _refuse_move("No walkable deck at that point.")
	# On a warped scene (e.g. the channels helix), the click lands on the MODEL deck — map it back to a
	# flat (s, lane) target so all the grid/move logic below runs in the flat data frame.
	# A hover preview already resolved one exact graph vertex. Reconstruct its
	# data-space point before any warped inverse so commit cannot lose the cached
	# level or alias a same-XZ floor.
	if game_state != null and not cached_navigation_location.is_empty() \
			and grid_world != null \
			and cached_navigation_location.get("cell", null) is Vector2i:
		world_pos = grid_world.grid_to_world(
			cached_navigation_location["cell"] as Vector2i,
			int(cached_navigation_location.get(
				"level", game_state.get_character_level(char_id))))
	elif captured_data_position.is_finite():
		world_pos = captured_data_position
	elif game_state != null and game_state.coord_map != null:
		world_pos = _ground_hit_to_data(world_pos)
		if not world_pos.is_finite():
			return _refuse_move("No walkable deck at that point.")
	# Grid input resolves once to a stable `(cell, level)` identity. A cached hover destination and a
	# fresh raw ray therefore enter the exact same command boundary.
	if game_state != null and char_id != "" and grid_world != null:
		if grid_world.level_count <= 1 \
				and absf(world_pos.y - game_state.get_position(char_id).y) > LEVEL_GAP:
			return _refuse_move("That deck needs a visible traversal.")
		var navigation_location := cached_navigation_location.duplicate(true)
		if navigation_location.is_empty():
			navigation_location = game_state.resolve_navigation_location(char_id, world_pos)
		if navigation_location.is_empty():
			return _refuse_move("No walkable deck at that point.")
		var target_level := int(navigation_location.get(
			"level", game_state.get_character_level(char_id)))
		var cross_floor := target_level != game_state.get_character_level(char_id)
		if cross_floor and group_move:
			return _refuse_move(
				"Split the selection; the party cannot use that traversal together.")
		if cancel_interaction and _interaction_controller != null:
			_interaction_controller.cancel_active_target()
		if group_move:
			var group_cell: Vector2i = navigation_location["cell"]
			if game_state.party_move_to_cell(group_cell) <= 0:
				return _refuse_move("No selected party member can reach that deck.")
		else:
			if not game_state.command_move_to_navigation_location(
					char_id, navigation_location):
				return _refuse_move("No traversal connects to that deck." \
					if cross_floor else "No route to that deck.")
		_moving = true
		return true

	var cross_floor := game_state != null and char_id != "" \
		and absf(world_pos.y - game_state.get_position(char_id).y) > LEVEL_GAP
	# Otherwise reject a free walk across a large vertical gap (gridless stacked floors): the
	# character would just lerp through the air to it.
	if cross_floor:
		if group_move:
			return _refuse_move("Split the selection; the party cannot use that traversal together.")
		return _refuse_move("That deck needs a visible traversal.")
	if cancel_interaction and _interaction_controller != null:
		_interaction_controller.cancel_active_target()
	# Group move: one click moves the whole party. On a grid they spread onto
	# distinct cells; gridless (e.g. the elevator) they fan out around the clicked
	# point — either way every selected member gets a move, not just the active one.
	if group_move and game_state:
		var moved := game_state.party_move_to_pos(world_pos)
		if moved <= 0:
			return _refuse_move("No selected party member can reach that deck.")
		_moving = true
		return true
	if game_state and char_id != "":
		if not game_state.command_move_to_pos(char_id, world_pos):
			return _refuse_move("No route to that point.")
		_moving = true
		return true

	if grid_world:
		var target_cell := grid_world.world_to_grid(world_pos)
		var current_cell := grid_world.world_to_grid(global_position)
		var path := grid_world.find_path(current_cell, target_cell)
		if path.is_empty():
			return _refuse_move("No route to that deck.")
		walk_path(path)
	else:
		_target_pos = world_pos
		_moving = true
		_auto_path.clear()
		_auto_path_index = 0
	return true

func move_to_world_position(world_pos: Vector3) -> bool:
	return _set_click_target(world_pos, false)

func bind_interaction_root(root: Node) -> void:
	if _interaction_controller != null:
		_interaction_controller.bind_interaction_root(root)
	elif root != null and not _pending_interaction_roots.has(root):
		_pending_interaction_roots.append(root)

func bind_interaction_target(target: Node) -> void:
	if _interaction_controller != null:
		_interaction_controller.bind_interaction_target(target)
	elif target != null and not _pending_interaction_targets.has(target):
		_pending_interaction_targets.append(target)

func cancel_interaction_target() -> void:
	if _interaction_controller != null:
		_interaction_controller.cancel_active_target()

## Walk to a grid cell.
func walk_to_grid(cell: Vector2i) -> void:
	if game_state and char_id != "":
		game_state.command_move_to_cell(char_id, cell)
		_moving = true
		return
	if not grid_world:
		return
	var current_cell := grid_world.world_to_grid(global_position)
	var path := grid_world.find_path(current_cell, cell)
	if not path.is_empty():
		walk_path(path)

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var perf_started := PerformanceTrace.begin()
	# The sequence advances GameState in its parent `_process`, after fixed physics may
	# already have run for this rendered frame. Sync again before drawing so sloped and
	# typed multi-level edges never present the previous simulation sample.
	_sync_authoritative_transform()
	_update_hover_grid()
	PerformanceTrace.end(&"update", &"player.process", perf_started, char_id, 1)


func _sync_authoritative_transform() -> void:
	if game_state == null or char_id == "" or not game_state.characters.has(char_id):
		return
	global_position = game_state.get_render_position(char_id)

## Follow the cursor with the target-cell grid every frame. We POLL the viewport mouse position
## rather than react to InputEventMouseMotion: motion events don't reliably reach _unhandled_input
## in every host (they don't in headless, and a Control can swallow them), and polling also re-snaps
## the grid when the follow-camera pans under a stationary cursor. The raycast only runs for the
## active, move-enabled player (others gate out before it), so it's one cheap ray per frame.
func _update_hover_grid() -> void:
	if _hover_grid == null:
		return
	if _external_path_preview_active:
		_hover_grid.visible = false
		return
	var vp := get_viewport()
	if vp == null:
		_hover_grid.visible = false
		return
	# A stationary cursor over a stationary character changes nothing — skip the per-frame
	# raycast + preview work entirely (an unconditional ray would run 60x/sec for nothing).
	var mouse := vp.get_mouse_position()
	var self_moving := game_state != null and char_id != "" and game_state.is_moving(char_id)
	var graph_revision := _current_navigation_graph_revision()
	var camera := vp.get_camera_3d()
	var camera_instance_id := -1
	var camera_transform := Transform3D.IDENTITY
	var camera_projection := Projection()
	if camera != null:
		camera_instance_id = camera.get_instance_id()
		camera_transform = camera.global_transform
		camera_projection = camera.get_camera_projection()
	var camera_unchanged := camera_instance_id == _hover_last_camera_instance_id \
			and camera_transform == _hover_last_camera_transform \
			and camera_projection == _hover_last_camera_projection
	if mouse.is_equal_approx(_hover_last_mouse) and not self_moving \
			and graph_revision == _hover_last_graph_revision and camera_unchanged:
		return
	_hover_last_mouse = mouse
	_hover_last_graph_revision = graph_revision
	_hover_last_camera_instance_id = camera_instance_id
	_hover_last_camera_transform = camera_transform
	_hover_last_camera_projection = camera_projection
	_update_hover_from_screen(mouse)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var perf_started := PerformanceTrace.begin()
	if game_state and char_id != "":
		if game_state.is_moving(char_id):
			# This node's origin is its feet; the mesh/collider carry their own local body lift.
			# Mirror the complete authoritative transform so level changes cannot retain a stale Y.
			_sync_authoritative_transform()
			_moving = true
		elif _moving:
			_moving = false
			_sync_authoritative_transform()
			velocity = Vector3.ZERO
			arrived.emit()
			auto_path_complete.emit()
		else:
			# Idle presenters remain exact too: this keeps warped decks and authored full-XYZ resets aligned.
			# never moves (or has arrived) sits at its flat data position — below the curved deck.
			_sync_authoritative_transform()
		_update_path_line()
		PerformanceTrace.end(&"update", &"player.physics_process", perf_started, char_id, 1)
		return

	if _auto_path.size() > 0:
		var waypoint := _auto_path[_auto_path_index]
		var dir := (waypoint - global_position)
		dir.y = 0
		if dir.length() < 0.2:
			_auto_path_index += 1
			if _auto_path_index >= _auto_path.size():
				_auto_path.clear()
				_auto_path_index = 0
				_moving = false
				auto_path_complete.emit()
				_update_path_line()
				PerformanceTrace.end(&"update", &"player.physics_process", perf_started, char_id, 1)
				return
		else:
			velocity = dir.normalized() * move_speed
			move_and_slide()
		_update_path_line()
		PerformanceTrace.end(&"update", &"player.physics_process", perf_started, char_id, 1)
		return

	if _moving:
		var dir := (_target_pos - global_position)
		dir.y = 0
		var dist := dir.length()
		if dist < 0.15:
			_moving = false
			velocity = Vector3.ZERO
			arrived.emit()
		else:
			velocity = dir.normalized() * move_speed
			move_and_slide()

	_update_path_line()
	PerformanceTrace.end(&"update", &"player.physics_process", perf_started, char_id, 1)

func _on_gs_arrived(id: String) -> void:
	if id == char_id:
		# Scheduler completion can clear `is_moving` before the next physics sample. Snap the feet
		# node here so ordinary legs and typed edge landings cannot stop one frame short in Y.
		_sync_authoritative_transform()
		_moving = false
		arrived.emit()
		auto_path_complete.emit()

func _update_path_line() -> void:
	var has_queued_ability := game_state and char_id != "" and game_state.has_queued_ability(char_id)
	if has_queued_ability:
		var qa_data: Dictionary = game_state._queued_abilities[char_id]
		_ability_marker.global_position = qa_data.target_pos + Vector3(0.0, 0.5, 0.0)
		var pulse := 0.5 + sin(Time.get_ticks_msec() * 0.005) * 0.3  # @rendering_only — ability marker pulse
		_ability_marker_mat.albedo_color.a = pulse
	else:
		_ability_marker_mat.albedo_color.a = 0.0


## Walk to a world position.
func walk_to(pos: Vector3) -> void:
	if game_state and char_id != "":
		game_state.command_move_to_pos(char_id, pos)
		_moving = true
		return
	_auto_path = [pos]
	_auto_path_index = 0
	_moving = true

## Walk through waypoints.
func walk_path(path: Array[Vector3]) -> void:
	if game_state and char_id != "":
		game_state.command_walk_path(char_id, path)
		_moving = true
		return
	_auto_path = path
	_auto_path_index = 0
	_moving = true

func set_move_enabled(enabled: bool) -> void:
	_move_enabled = enabled
	if not enabled:
		if game_state and char_id != "":
			game_state.command_stop(char_id)
		_moving = false
		velocity = Vector3.ZERO
		_auto_path.clear()


## Change only the input gate around an already-authoritative GameState plan. Selection changes and
## save attachment must not call set_move_enabled(false), because that API deliberately commits a
## stop command and would turn every in-flight order/snapshot into a parked body.
func restore_move_input_enabled(enabled: bool) -> void:
	_move_enabled = enabled


func is_move_enabled() -> bool:
	return _move_enabled

func is_moving() -> bool:
	if game_state and char_id != "":
		return game_state.is_moving(char_id)
	return _moving

func set_running(running: bool) -> void:
	_running = running
	if _mesh:
		if running:
			_mesh.rotation.x = -0.15
			_mesh.scale = Vector3(0.9, 1.1, 0.9)
		else:
			_mesh.rotation.x = 0.0
			_mesh.scale = Vector3.ONE
