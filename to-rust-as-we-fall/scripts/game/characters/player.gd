@tool
extends CharacterBody3D

const CHARACTER_INTERACTION_CONTROLLER := preload("res://scripts/game/characters/character_interaction_controller.gd")

## Click-to-move character view. Prefer GameState; fallback moves locally.

@export var move_speed := 3.0
@export var run_speed := 6.0
@export var color := Color(0.29, 0.62, 1.0)  # Aster blue

## A free click whose target floor sits more than this far above/below the character's current
## level is rejected — they can't walk through the air to a different floor (which would just lerp
## the Y and "float between levels"). Flat scenes click same-Y floors, so this only bites where
## floors are stacked (the elevator); scripted moves bypass _set_click_target entirely.
const LEVEL_GAP := 1.6

## Optional A* grid.
var grid_world: GridWorld

## Optional authoritative state.
var game_state: GameState
var char_id := ""  ## Character ID in GameState (e.g. "aster")

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

var _dest_marker: MeshInstance3D
var _dest_marker_mat: StandardMaterial3D

# Hover grid: hovering the floor in move mode reveals a grid patch with the pointed-at cell lit, so
# you can see exactly where a click will move you. Cosmetic; follows the cursor, snapped to cells.
const HOVER_CELL := 1.0
const HOVER_SPAN := 3            # NxN grid patch shown around the hovered cell
const HOVER_TINT := Color(1.0, 1.0, 1.0)  # faded white — a quiet aim hint, not a character-coloured beacon
const HOVER_LIFT := 0.05         # the flat grid quad sits this far above the hovered floor point
var _hover_grid: MeshInstance3D

# Path preview: while hovering the floor in move mode, show (dim) the route a click WOULD take, before
# committing it. Recomputed only when the hovered cell changes (per-frame pathfinding would be wasteful).
const PREVIEW_COLOR := Color(0.55, 0.7, 0.85)  # muted blue-grey, distinct from the bright committed path
var _path_preview: PathRenderer
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
var _preview_last_cell := Vector2i(0x7fffffff, 0x7fffffff)


signal arrived()
signal auto_path_complete()
## Emitted on every left-click that hits the ground, with the world position.
## Sequences listen to this instead of running their own ground raycast.
signal ground_clicked(world_pos: Vector3)

func _ready() -> void:
	_target_pos = global_position

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

	_dest_marker = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.2
	torus.outer_radius = 0.3
	torus.rings = 16
	torus.ring_segments = 8
	_dest_marker.mesh = torus
	_dest_marker_mat = StandardMaterial3D.new()
	_dest_marker_mat.albedo_color = Color(color, 0.0)
	_dest_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dest_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dest_marker.material_override = _dest_marker_mat
	_dest_marker.rotation.x = -PI / 2.0
	_dest_marker.top_level = true
	add_child(_dest_marker)

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

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton

	# The `command` action (right mouse) is the RTS move command. A command ON an interactable is
	# consumed by that object first (it interacts instead), so it only reaches here for plain ground.
	if mb.is_action_pressed("command"):
		if _push_obj_id != "":
			var push_hit := _raycast_ground(mb.position)
			if push_hit != Vector3.INF:
				_commit_push(push_hit)
			return
		if _click_mode != "move" or not _move_enabled:
			return
		if _auto_path.size() > 0 and not (game_state and char_id != ""):
			return  # Don't interrupt fallback auto-path with clicks
		var rhit := _raycast_ground(mb.position)
		if rhit != Vector3.INF:
			ground_clicked.emit(rhit)
			_set_click_target(rhit)
		return

	# `select` (left mouse) during a sequence's "click the world target" beat only reports the ground
	# position; the sequence interprets it. The SelectionController yields `select` to us here
	# (is_pick_mode). In normal "move" mode `select` belongs to the SelectionController (character pick).
	# `select` while a push is queued = cancel the queue.
	if mb.is_action_pressed("select") and _push_obj_id != "":
		cancel_push_queue()
		return

	if mb.is_action_pressed("select") and _click_mode == "select":
		var hit_sel := _raycast_ground(mb.position)
		if hit_sel != Vector3.INF:
			ground_clicked.emit(hit_sel)

## Switch how a ground click is interpreted: "move" (default) or "select".
func set_click_mode(mode: String) -> void:
	_click_mode = mode if mode in ["move", "select"] else "move"

## True while a sequence beat wants the player to click a world TARGET (select-mode), not move.
## The SelectionController checks this to yield LEFT-click to player.gd's ground_clicked path.
func is_pick_mode() -> bool:
	return _click_mode != "move"

func _raycast_ground(screen_pos: Vector2) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return Vector3.INF
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	query.collision_mask = 1  # Ground only
	var result := space.intersect_ray(query)
	if not result.is_empty():
		return result.position
	return Vector3.INF

# --- Hover grid (target preview) ---

func _build_hover_grid() -> void:
	# A flat quad lying on the floor, textured with the grid IMAGE. UNSHADED so it shows at full
	# brightness regardless of scene light (the ferrolure chamber is dark), and ALPHA-transparent so the
	# gaps between lines stay see-through — a crisp grid, not the solid glowing blob a Decal's emission
	# channel bloomed into. A PlaneMesh is the XZ plane (faces +Y), so it sits flat under the cursor.
	_hover_grid = MeshInstance3D.new()
	_hover_grid.top_level = true   # authored in world space; we set its global position to the cell
	_hover_grid.visible = false
	var plane := PlaneMesh.new()
	plane.size = Vector2(HOVER_SPAN * HOVER_CELL, HOVER_SPAN * HOVER_CELL)
	_hover_grid.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# ALPHA_SCISSOR, not ALPHA: the alpha-BLEND pass doesn't composite in the preview's scene (Decals and
	# opaque meshes draw, alpha-blended meshes don't), so a blended grid was invisible. Scissor renders in
	# the OPAQUE pass and discards texels below the threshold — solid grid lines + see-through gaps. The
	# threshold also gives the falloff for free: faint outer lines fall under it and drop out.
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.3
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = _build_grid_texture()
	_hover_grid.material_override = mat
	add_child(_hover_grid)

## Per-player grid IMAGE in the player's colour: lines + a filled centre cell, with the ALPHA falling
## off radially from the centre so the pointed-at tile is strongly opaque and the grid dissolves toward
## the edges. The expensive falloff pattern is computed ONCE (shared alpha), then tinted per colour.
static var _grid_alpha: PackedFloat32Array
static var _grid_dim := 0

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
	var c_lo: int = (cells / 2) * cpx
	var c_hi: int = c_lo + cpx
	for y in range(dim):
		var fy := (y + 0.5 - half) / half
		var in_cy := y >= c_lo and y < c_hi
		for x in range(dim):
			var fx := (x + 0.5 - half) / half
			var falloff := pow(clampf(1.0 - sqrt(fx * fx + fy * fy), 0.0, 1.0), 1.6)
			var a := 0.0
			if in_cy and x >= c_lo and x < c_hi:
				a = 0.3                        # the target cell: present but faded
			elif is_line[x] or is_line[y]:
				a = 0.45 * falloff             # grid lines fade out toward the edges
			_grid_alpha[y * dim + x] = a

func _build_grid_texture() -> ImageTexture:
	_ensure_grid_alpha()
	var dim := _grid_dim
	var img := Image.create(dim, dim, false, Image.FORMAT_RGBA8)
	img.fill(Color(HOVER_TINT.r, HOVER_TINT.g, HOVER_TINT.b, 0.0))
	for y in range(dim):
		for x in range(dim):
			var a := _grid_alpha[y * dim + x]
			if a > 0.004:
				img.set_pixel(x, y, Color(HOVER_TINT.r, HOVER_TINT.g, HOVER_TINT.b, a))
	return ImageTexture.create_from_image(img)

## Raycast the floor under the cursor and show the grid there. Only in move mode while move-enabled,
## so it doesn't appear during selection prompts or for non-active party members.
func _update_hover_from_screen(screen_pos: Vector2) -> void:
	if _hover_grid == null:
		return
	if _click_mode != "move" or not _move_enabled:
		_hover_grid.visible = false
		_clear_path_preview()
		return
	var hit := _raycast_ground(screen_pos)
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
	# Centre the flat grid quad over the cell the cursor is over, just above the floor.
	var cx := floorf(hit.x) + HOVER_CELL * 0.5
	var cz := floorf(hit.z) + HOVER_CELL * 0.5
	_hover_grid.global_position = Vector3(cx, hit.y + HOVER_LIFT, cz)
	_hover_grid.visible = true
	_update_path_preview(hit)

## Show the would-be route to the hovered point (dim), before a click commits it. Recomputed only when
## the hovered CELL changes — per-frame pathfinding for a cosmetic line would be wasteful. Cleared while
## actually moving (the committed path shows then) and when not hovering the floor. With a party selected
## (group_move) it previews EVERY member's path to its own spread destination, not just the active one.
func _update_path_preview(hit: Vector3) -> void:
	if _path_preview == null or game_state == null or char_id == "":
		return
	if game_state.is_moving(char_id):
		_clear_path_preview()
		return
	var cell := Vector2i(int(floorf(hit.x)), int(floorf(hit.z)))
	if cell == _preview_last_cell:
		return
	_preview_last_cell = cell
	if group_move and game_state.get_party().size() > 1:
		_path_preview.clear_explicit_path()  # the per-member previews replace the single one
		_update_party_preview(hit)
		return
	_clear_party_preview()
	var path := game_state.compute_preview_path(char_id, hit)
	if path.size() >= 2:
		_path_preview.set_explicit_path(path, 1)  # from_index 1: the renderer prepends the live start point
	else:
		_path_preview.clear_explicit_path()

## One dim ribbon per selected member, each in that member's colour, anchored to that member so it starts
## at them. Mirrors the party spread, so the preview matches the click.
func _update_party_preview(hit: Vector3) -> void:
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
	for cid in _party_previews.keys():
		if not seen.has(cid):
			_party_previews[cid].clear_explicit_path()

func _clear_party_preview() -> void:
	for cid in _party_previews.keys():
		_party_previews[cid].clear_explicit_path()

## Enter queued-push mode for a pushable object (a command-click on its PushTarget got us here).
func queue_push(obj_id: String) -> void:
	_push_obj_id = obj_id
	_push_plan = {}
	_push_plan_cell = Vector2i(0x7fffffff, 0x7fffffff)
	_hover_last_mouse = Vector2(-1e9, -1e9)  # force a preview refresh

func is_push_queued() -> bool:
	return _push_obj_id != ""

func cancel_push_queue() -> void:
	_push_obj_id = ""
	_push_plan = {}
	_set_blocked_cursor(false)
	_clear_push_ghosts()
	_clear_path_preview()

## Hover while a push is queued: plan to the hovered cell; ghosts + the object's route when possible,
## the blocked (X) cursor when "there is not enough space".
func _update_push_preview(hit: Vector3) -> void:
	if game_state == null or game_state.grid == null or char_id == "":
		return
	var cell: Vector2i = game_state.grid.world_to_grid(hit)
	if cell == _push_plan_cell:
		return
	_push_plan_cell = cell
	_push_plan = game_state.plan_push_for(char_id, _push_obj_id, cell)
	if _push_plan.is_empty():
		_set_blocked_cursor(true)
		_clear_push_ghosts()
		_clear_path_preview()
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
	_ensure_push_ghosts()
	_push_ghost_obj.global_position = route[route.size() - 1] + Vector3(0, 0.45, 0)
	var char_end: Vector3 = game_state.grid.grid_to_world(
		(steps[steps.size() - 1] as Dictionary)["obj_from"] if not steps.is_empty() else game_state.grid.world_to_grid(global_position),
		game_state.get_character_level(char_id))
	_push_ghost_char.global_position = char_end + Vector3(0, 0.5, 0)
	_push_ghost_obj.visible = true
	_push_ghost_char.visible = true

func _commit_push(hit: Vector3) -> void:
	if game_state == null or game_state.grid == null:
		cancel_push_queue()
		return
	var cell: Vector2i = game_state.grid.world_to_grid(hit)
	if game_state.plan_push_for(char_id, _push_obj_id, cell).is_empty():
		return  # blocked destination: the operation does not occur (X cursor already shows why)
	game_state.command_push_object(char_id, _push_obj_id, cell)
	cancel_push_queue()

func _ensure_push_ghosts() -> void:
	if _push_ghost_char != null:
		return
	_push_ghost_char = MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.25
	cap.height = 1.0
	_push_ghost_char.mesh = cap
	_push_ghost_char.material_override = _ghost_material(_character_color())
	_push_ghost_char.top_level = true
	_push_ghost_char.visible = false
	add_child(_push_ghost_char)
	_push_ghost_obj = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.85, 0.9, 0.85)
	_push_ghost_obj.mesh = box
	_push_ghost_obj.material_override = _ghost_material(Color(0.8, 0.65, 0.4))
	_push_ghost_obj.top_level = true
	_push_ghost_obj.visible = false
	add_child(_push_ghost_obj)

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
	_clear_party_preview()
	_preview_last_cell = Vector2i(0x7fffffff, 0x7fffffff)  # force a recompute on the next hover

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

func _set_click_target(world_pos: Vector3, cancel_interaction := true) -> bool:
	var cross_floor := game_state != null and char_id != "" \
		and absf(world_pos.y - game_state.get_position(char_id).y) > LEVEL_GAP
	# A click on a different stacked floor: on a MULTI-LEVEL GRID, route over ladders/ramps to it
	# (walk to the ladder, climb, continue). Single-character moves only — party multi-floor isn't
	# wired yet, so a group click across floors stays rejected.
	if cross_floor and grid_world != null and grid_world.level_count > 1 and not group_move:
		if cancel_interaction and _interaction_controller != null:
			_interaction_controller.cancel_active_target()
		var dest_cell := grid_world.world_to_grid(world_pos)
		var dest_level := grid_world.level_for_y(world_pos.y)
		if not game_state.command_move_cross_level(char_id, dest_cell, dest_level):
			return false
		var dest_snap := grid_world.grid_to_world(dest_cell, dest_level)
		_dest_marker.global_position = Vector3(dest_snap.x, dest_snap.y + 0.05, dest_snap.z)
		_moving = true
		_dest_marker_mat.albedo_color.a = 0.6
		_dest_marker.scale = Vector3(1.2, 1.2, 1.2)
		return true
	# Otherwise reject a free walk across a large vertical gap (gridless stacked floors): the
	# character would just lerp through the air to it.
	if cross_floor:
		return false
	if cancel_interaction and _interaction_controller != null:
		_interaction_controller.cancel_active_target()
	# Group move: one click moves the whole party. On a grid they spread onto
	# distinct cells; gridless (e.g. the elevator) they fan out around the clicked
	# point — either way every selected member gets a move, not just the active one.
	if group_move and game_state:
		if grid_world:
			var group_cell := grid_world.world_to_grid(world_pos)
			game_state.party_move_to_cell(group_cell)
			var group_snap := grid_world.grid_to_world(group_cell)
			_dest_marker.global_position = Vector3(group_snap.x, 0.05, group_snap.z)
		else:
			game_state.party_move_to_pos(world_pos)
			_dest_marker.global_position = Vector3(world_pos.x, world_pos.y + 0.05, world_pos.z)
		_moving = true
		_dest_marker_mat.albedo_color.a = 0.6
		_dest_marker.scale = Vector3(1.2, 1.2, 1.2)
		return true
	if game_state and char_id != "":
		if grid_world:
			var target_cell := grid_world.world_to_grid(world_pos)
			if not game_state.command_move_to_cell(char_id, target_cell):
				return false
			var snapped_pos := grid_world.grid_to_world(target_cell)
			_dest_marker.global_position = Vector3(snapped_pos.x, 0.05, snapped_pos.z)
		else:
			if not game_state.command_move_to_pos(char_id, world_pos):
				return false
			_dest_marker.global_position = Vector3(world_pos.x, world_pos.y + 0.05, world_pos.z)
		_moving = true
		_dest_marker_mat.albedo_color.a = 0.6
		_dest_marker.scale = Vector3(1.2, 1.2, 1.2)
		return true

	if grid_world:
		var target_cell := grid_world.world_to_grid(world_pos)
		var current_cell := grid_world.world_to_grid(global_position)
		var snapped_pos := grid_world.grid_to_world(target_cell)
		var path := grid_world.find_path(current_cell, target_cell)
		if path.is_empty():
			return false
		walk_path(path)
		_dest_marker.global_position = Vector3(snapped_pos.x, 0.05, snapped_pos.z)
		_dest_marker_mat.albedo_color.a = 0.6
		_dest_marker.scale = Vector3(1.2, 1.2, 1.2)
	else:
		_target_pos = world_pos
		_moving = true
		_auto_path.clear()
		_auto_path_index = 0
		_dest_marker.global_position = Vector3(world_pos.x, world_pos.y + 0.05, world_pos.z)
		_dest_marker_mat.albedo_color.a = 0.6
		_dest_marker.scale = Vector3(1.2, 1.2, 1.2)
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
	_update_hover_grid()

## Follow the cursor with the target-cell grid every frame. We POLL the viewport mouse position
## rather than react to InputEventMouseMotion: motion events don't reliably reach _unhandled_input
## in every host (they don't in headless, and a Control can swallow them), and polling also re-snaps
## the grid when the follow-camera pans under a stationary cursor. The raycast only runs for the
## active, move-enabled player (others gate out before it), so it's one cheap ray per frame.
func _update_hover_grid() -> void:
	if _hover_grid == null:
		return
	var vp := get_viewport()
	if vp == null:
		_hover_grid.visible = false
		return
	# A stationary cursor over a stationary character changes nothing — skip the per-frame
	# raycast + preview work entirely (the raycast used to run 60x/sec regardless).
	var mouse := vp.get_mouse_position()
	var self_moving := game_state != null and char_id != "" and game_state.is_moving(char_id)
	if mouse.is_equal_approx(_hover_last_mouse) and not self_moving:
		return
	_hover_last_mouse = mouse
	_update_hover_from_screen(mouse)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if game_state and char_id != "":
		if game_state.is_moving(char_id):
			var pos := game_state.get_position(char_id)
			if grid_world:
				global_position = Vector3(pos.x, global_position.y, pos.z)
			else:
				global_position = pos
			_moving = true
		elif _moving:
			_moving = false
			var pos := game_state.get_position(char_id)
			if grid_world:
				global_position = Vector3(pos.x, global_position.y, pos.z)
			else:
				global_position = pos
			velocity = Vector3.ZERO
			arrived.emit()
			auto_path_complete.emit()
		_update_dest_marker(delta)
		_update_path_line()
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
				_update_dest_marker(delta)
				_update_path_line()
				return
		else:
			velocity = dir.normalized() * move_speed
			move_and_slide()
		_update_path_line()
		_update_dest_marker(delta)
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

	_update_dest_marker(delta)
	_update_path_line()

func _on_gs_arrived(id: String) -> void:
	if id == char_id:
		_moving = false
		arrived.emit()
		auto_path_complete.emit()

func _update_dest_marker(delta: float) -> void:
	if _moving:
		var pulse := 0.3 + sin(Time.get_ticks_msec() * 0.004) * 0.15  # @rendering_only — destination marker pulse
		_dest_marker_mat.albedo_color.a = pulse
		var dist := Vector2(
			global_position.x - _dest_marker.global_position.x,
			global_position.z - _dest_marker.global_position.z
		).length()
		var s := clampf(dist / 3.0, 0.3, 1.2)
		_dest_marker.scale = Vector3(s, s, s)
	else:
		_dest_marker_mat.albedo_color.a = maxf(0, _dest_marker_mat.albedo_color.a - delta * 2.0)

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
	if _dest_marker_mat:
		if running:
			_dest_marker_mat.albedo_color = Color(1.0, 0.6, 0.2, _dest_marker_mat.albedo_color.a)
		else:
			_dest_marker_mat.albedo_color = Color(color.r, color.g, color.b, _dest_marker_mat.albedo_color.a)
