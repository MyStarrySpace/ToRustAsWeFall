class_name PortalPad
extends Interactable

## A PORTAL PAD: the in-world, clickable realization of a "portal" (GDD: the teleport network that eliminates
## backtracking). The abstract zone-graph EDGE is the `Portal` RefCounted data class; THIS is the physical pad a
## member steps onto. Click it and the activating member (whoever arrives first) steps through to the paired
## destination — bidirectional (place two pointed at each other) and reusable, so a member can return.
## Only the one who activated it crosses; it never moves the whole party.
##
## Self-contained + reusable like Flure: owns its glow visual, its outline/hover wiring (consistent highlight), and
## its teleport logic. A fragment composes it (place + give it a destination); a level builder will too.
##
## GROUP CROSSING: when the ACTIVATOR belongs to the current selection (the loader installs a
## group provider), the whole selection QUEUES through — one member at a time, each teleporting and
## then walking OFF the receiving pad to its own arrival slot so the next can step in. Hovering the
## pad previews GHOSTS standing on those final slots; compute_group_arrivals is the ONE function
## both the ghosts and the committed queue read, so the preview cannot lie. An activator outside
## the selection crosses alone (the original solo semantics).

signal stepped_through(who: String, dest: Vector3)
signal group_crossing_finished(ids: Array)

const GROUP_CLEAR_GAP := 0.15        # breath between one member clearing the pad and the next stepping in
const ARRIVAL_RING_RADIUS := 1.7     # the walk-off fan on the far side

@export var glow_color := Color(0.55, 0.42, 0.98)
@export var glow_radius := 0.5

var _gs   # GameState (Interactable keeps its own _game_state for data binding; we hold our own for the teleport)
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _dest := Vector3.ZERO
var _data_authored := false
var _source_data := Vector3.ZERO
var _dest_data := Vector3.ZERO
var _group_provider: Callable = Callable()   # -> Array of selected char ids (the loader installs it)
var _queue: Array = []
var _queue_arrivals: Array = []
var _queue_i := 0
var _ghosts: Array = []

## Configure BEFORE adding to the tree. `dest_world` is the paired portal's position this one sends you to.
func configure(gs, world_pos: Vector3, dest_world: Vector3, radius := 1.2,
		color := Color(0.55, 0.42, 0.98)) -> void:
	_data_authored = false
	_gs = gs
	position = world_pos
	_dest = dest_world
	interaction_radius = radius
	glow_color = color
	interactable_type = InteractableType.INSPECTION
	one_shot = false   # reusable: step through, and back
	description = "Step through"
	tutorial_label = "PORTAL"

## Configure in GameState data coordinates while allowing the pad, destination, ghosts, and hover fan to
## render through a later-installed coord map. The canonical destination never becomes a warped world point,
## so a portal authored before the environment model loads cannot double-convert its arrival.
func configure_data(gs, source_data: Vector3, dest_data: Vector3, radius := 1.2,
		color := Color(0.55, 0.42, 0.98)) -> void:
	configure(gs, source_data, dest_data, radius, color)
	_data_authored = true
	_source_data = source_data
	_dest_data = dest_data
	set_meta("flat_authored_position", source_data)
	if _gs != null and _gs.coord_map != null:
		position = _gs.coord_map.to_world(source_data)

func get_data_source() -> Vector3:
	return _source_data if _data_authored else position

func get_data_destination() -> Vector3:
	return _dest_data if _data_authored else _destination_data()

func _destination_world() -> Vector3:
	if _data_authored and _gs != null and _gs.coord_map != null:
		return _gs.coord_map.to_world(_dest_data)
	return _dest_data if _data_authored else _dest

func _destination_data() -> Vector3:
	if _data_authored:
		return _dest_data
	if _gs != null and _gs.coord_map != null:
		return _gs.coord_map.to_data(_dest)
	return _dest

func _arrival_world_to_data(world: Vector3) -> Vector3:
	if _gs != null and _gs.coord_map != null:
		return _gs.coord_map.to_data(world)
	return world

func _snap_arrival_world(world: Vector3) -> Vector3:
	if _gs == null or _gs.grid == null or not _gs.grid.has_method("nearest_walkable_world"):
		return world
	if _gs.coord_map != null:
		var data: Vector3 = _gs.coord_map.to_data(world)
		data = _gs.grid.nearest_walkable_world(data)
		return _gs.coord_map.to_world(data)
	return _gs.grid.nearest_walkable_world(world)

func _ready() -> void:
	if get_node_or_null("CollisionShape3D") == null:
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		var sh := SphereShape3D.new()
		sh.radius = interaction_radius
		cs.shape = sh
		add_child(cs)
	_glow = _build_glow()
	super._ready()
	_wire_outline()
	if not interacted.is_connected(_on_interacted):
		interacted.connect(_on_interacted)

func _build_glow() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Glow"
	var sph := SphereMesh.new()
	sph.radius = glow_radius
	sph.height = glow_radius * 2.0
	mi.mesh = sph
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.albedo_color = glow_color * 0.5
	_glow_mat.emission_enabled = true
	_glow_mat.emission = glow_color
	_glow_mat.emission_energy_multiplier = 0.8
	mi.material_override = _glow_mat
	mi.position = Vector3(0.0, 0.6, 0.0)
	add_child(mi)
	return mi

func _wire_outline() -> void:
	var mgr := OutlineFeedbackManager.ensure(self)
	if mgr == null or _glow == null:
		return
	var target := mgr.outline_meshes(self, str(name) + "Outline", [_glow], "portal", maxf(1.0, interaction_radius))
	if target == null:
		return
	if target is Node3D and _glow is Node3D:
		(target as Node3D).global_position = (_glow as Node3D).global_position
	if target.has_method("set_interaction_delegate"):
		target.call("set_interaction_delegate", self)
	set_outline_target(target)

## A STUNNED portal refuses all transit until the stun expires (the Hushbloom portal-stun — the
## chase framework's expert-solution mechanic: sealing both of an offshoot's portals makes it a
## locked pocket). Pure tick check; the glow dims while sealed.
var _stunned_until := -1.0

func stun(duration: float) -> void:
	if _gs == null or _gs.scheduler == null:
		return
	_stunned_until = float(_gs.scheduler.get_current_tick()) + duration
	if _glow_mat != null:
		_glow_mat.emission_energy_multiplier = 0.08
	_gs.scheduler.schedule_after(duration + 0.05, _refresh_stun_visual, _hop_tag() + "_stun")

func is_stunned() -> bool:
	return _gs != null and _gs.scheduler != null 		and float(_gs.scheduler.get_current_tick()) < _stunned_until

func _refresh_stun_visual() -> void:
	if not is_stunned() and _glow_mat != null:
		_glow_mat.emission_energy_multiplier = 1.6

func _on_interacted() -> void:
	if is_stunned():
		return
	var group := _group_for(str(active_character))
	if group.size() <= 1:
		step_through()
	else:
		step_group_through(group)

## The loader hands the pad a way to read the CURRENT selection, so a click can move the party.
func set_group_provider(provider: Callable) -> void:
	_group_provider = provider

## Who a click sends through: the selection with the activator leading, when the activator belongs
## to it; otherwise just the activator (solo semantics — the wash-intro one-at-a-time teach).
func _group_for(activator: String) -> Array:
	var sel: Array = []
	if _group_provider.is_valid():
		for v in (_group_provider.call() as Array):
			var cid := str(v)
			if _gs != null and _gs.characters.has(cid) and not _gs.is_downed(cid) and not sel.has(cid):
				sel.append(cid)
	if activator != "" and sel.has(activator):
		sel.erase(activator)
		sel.push_front(activator)
		return sel
	if activator != "":
		return [activator]
	return sel

## The far-side arrival slots — a walk-off fan pointing AWAY along the travel direction so nobody
## parks on the receiving pad. Pure + deterministic: hover ghosts and the committed queue both read
## THIS, so the preview always matches the crossing.
func compute_group_arrivals(ids: Array) -> Array:
	var out: Array = []
	var dest_world := _destination_world()
	var away := dest_world - global_position
	away.y = 0.0
	var base_angle := atan2(away.z, away.x) if away.length() > 0.01 else 0.0
	for i in range(ids.size()):
		var ang := base_angle + (float(i) - (float(ids.size()) - 1.0) * 0.5) * 0.9
		var pos := dest_world + Vector3(cos(ang), 0.0, sin(ang)) * ARRIVAL_RING_RADIUS
		pos.y = dest_world.y
		pos = _snap_arrival_world(pos)
		out.append(pos)
	return out

## Queue the whole group through: one member per hop — teleport, walk off to the slot, and the next
## steps in once the walk-off plan ENDS (read analytically off the scheduler; replay reproduces the
## crossing from the logged snap+move pairs alone).
func step_group_through(ids: Array) -> bool:
	if is_stunned():
		return false
	if _gs == null or ids.is_empty() or not _queue.is_empty():
		return false
	_queue = ids.duplicate()
	_queue_arrivals = compute_group_arrivals(ids)
	_queue_i = 0
	_hop_next()
	return true

func _hop_next() -> void:
	if _gs == null or _queue_i >= _queue.size():
		var done := _queue.duplicate()
		_queue.clear()
		if not done.is_empty():
			group_crossing_finished.emit(done)
		return
	var who := str(_queue[_queue_i])
	var slot: Vector3 = _queue_arrivals[_queue_i]
	_queue_i += 1
	if _gs.characters.has(who) and not _gs.is_downed(who):
		_gs.command_stop(who)
		var dest := _destination_data()
		var slot_d := _arrival_world_to_data(slot)
		_gs.snap_character_to(who, dest)
		_gs.command_move_to_pos(who, slot_d)
		stepped_through.emit(who, dest)
	var sched = _gs.scheduler
	if sched == null:
		_hop_next()
		return
	var wait := GROUP_CLEAR_GAP
	if _gs.has_method("get_plan_end_tick") and _gs.characters.has(who):
		var end_tick: float = _gs.get_plan_end_tick(who)
		if end_tick >= 0.0:
			wait = maxf(GROUP_CLEAR_GAP, end_tick - sched.get_current_tick() + GROUP_CLEAR_GAP)
	sched.cancel_tag(_hop_tag())
	sched.schedule_after(wait, _hop_next, _hop_tag())

func _hop_tag() -> String:
	return "portal_hop_" + str(name)

# --- Hover ghosts: the party's FINAL positions on the far side, before anyone commits. ---

func set_hover_feedback(active: bool) -> void:
	super.set_hover_feedback(active)
	_update_ghosts(active)

func _update_ghosts(show_ghosts: bool) -> void:
	for g in _ghosts:
		if is_instance_valid(g):
			g.queue_free()
	_ghosts.clear()
	if not show_ghosts or _gs == null:
		return
	var ids: Array = []
	if _group_provider.is_valid():
		for v in (_group_provider.call() as Array):
			var cid := str(v)
			if _gs.characters.has(cid) and not _gs.is_downed(cid) and not ids.has(cid):
				ids.append(cid)
	if ids.is_empty() and active_character != "" and _gs.characters.has(str(active_character)):
		ids = [str(active_character)]
	if ids.is_empty():
		return
	var slots := compute_group_arrivals(ids)
	for i in range(slots.size()):
		var ghost := MeshInstance3D.new()
		ghost.name = "PortalGhost_%d" % i
		var cap := CapsuleMesh.new()
		cap.radius = 0.32
		cap.height = 1.15
		ghost.mesh = cap
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(glow_color.r, glow_color.g, glow_color.b, 0.35)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.emission_enabled = true
		m.emission = glow_color
		m.emission_energy_multiplier = 0.6
		ghost.material_override = m
		add_child(ghost)
		ghost.global_position = (slots[i] as Vector3) + Vector3(0.0, 0.6, 0.0)
		_ghosts.append(ghost)

func _exit_tree() -> void:
	if _gs != null and _gs.scheduler != null:
		_gs.scheduler.cancel_tag(_hop_tag())

## Step the activating member (active_character) through to the paired destination.
func step_through() -> bool:
	if _gs == null or is_stunned():
		return false
	var who := str(active_character)
	if who == "" or not _gs.characters.has(who):
		return false
	_gs.command_stop(who)
	var dest := _destination_data()
	_gs.snap_character_to(who, dest)
	stepped_through.emit(who, dest)
	return true
