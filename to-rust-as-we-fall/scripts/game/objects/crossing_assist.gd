class_name CrossingAssist
extends Interactable

## The PERFECT-LAUNCH read — the Balancing Basin's RESOURCE branch (docs/BALANCING_BASIN.md).
## An authored console at a crossing lip: the required character logs the read, pays STAMINA
## from the closed bar, and the selected group is HELD at the lip and LAUNCHED on the exact
## commit of the target water state — the full window, no manual timing. Scoped to the NEXT
## window only (perfection without foresight); a cooldown prices repeat reads; a read that
## cannot pay simply fails (no charge, no arm). Extracted from the wash relay FlowTerminal
## grammar (hold-at-lip, depart-on-the-beat): the hold and the launch are ordinary logged
## movement commands, so an assisted crossing replays exactly.

signal read_logged(launch_tick: float)
signal read_refused(reason: String)
signal crossing_launched()

const LAUNCH_SETTLE_DELAY := 0.05   # launch just after the commit so the maps have flipped

const LIP_SLOTS: Array[Vector3] = [
	Vector3.ZERO, Vector3(1.5, 0.0, 0.0), Vector3(0.0, 0.0, -1.5),
	Vector3(-1.5, 0.0, 0.0), Vector3(1.5, 0.0, -1.5), Vector3(-1.5, 0.0, -1.5),
]
const DEST_SLOTS: Array[Vector3] = [
	Vector3.ZERO, Vector3(1.5, 0.0, 0.0), Vector3(-1.5, 0.0, 0.0),
	Vector3(0.0, 0.0, 1.5), Vector3(1.5, 0.0, 1.5), Vector3(-1.5, 0.0, 1.5),
]

var _gs = null
var _basin_tag := "basin"
var _basin_resolver := Callable()
var _group_provider := Callable()
var _lip := Vector3.ZERO
var _dest := Vector3.ZERO
var _target_state := 1
var _stamina_cost := 25.0
var _cooldown := 10.0
var _tag := "crossing_assist"
var _cooldown_until := -1.0
var _armed_launch_tick := -1.0
var _armed_ids: Array = []
var _screen_mat: StandardMaterial3D = null

## Configure BEFORE adding to the tree. All policy is data: the lip (hold point), the dest,
## the basin (by tag), the target state, and the two prices (stamina + cooldown).
func configure(gs, spec: Dictionary) -> void:
	_gs = gs
	position = spec.get("pos", Vector3.ZERO)
	_lip = spec.get("lip", position)
	_dest = spec.get("dest", position)
	_basin_tag = str(spec.get("basin_tag", "basin"))
	_target_state = int(spec.get("target_state", 1))
	_stamina_cost = maxf(0.0, float(spec.get("stamina_cost", 25.0)))
	_cooldown = maxf(0.0, float(spec.get("cooldown", 10.0)))
	_tag = str(spec.get("tag", "assist_%s" % _basin_tag))
	required_character = str(spec.get("required_character", "aster"))
	interaction_radius = float(spec.get("radius", 1.4))
	description = str(spec.get("desc", "Log the rota and cross on the beat"))
	tutorial_label = str(spec.get("label", "LOG THE ROTA"))
	interactable_type = InteractableType.INSPECTION
	if not interacted.is_connected(_on_read):
		interacted.connect(_on_read)

func set_basin_resolver(resolver: Callable) -> void:
	_basin_resolver = resolver

func set_group_provider(provider: Callable) -> void:
	_group_provider = provider

func is_read_armed() -> bool:
	return _armed_launch_tick >= 0.0

func cooldown_remaining() -> float:
	var sched = _scheduler_ref()
	if sched == null or _cooldown_until < 0.0:
		return 0.0
	return maxf(0.0, _cooldown_until - float(sched.get_current_tick()))

func reset_assist() -> void:
	var sched = _scheduler_ref()
	if sched != null:
		sched.cancel_tag(_tag + "_launch")
	_cooldown_until = -1.0
	_armed_launch_tick = -1.0
	_armed_ids.clear()
	_set_screen_lit(false)

func _ready() -> void:
	super._ready()
	_build_visual()
	call_deferred("_wire_console_outline")

func _on_read() -> void:
	var sched = _scheduler_ref()
	var basin: Variant = _resolve_basin()
	if sched == null or basin == null or _gs == null:
		read_refused.emit("no basin")
		return
	var now := float(sched.get_current_tick())
	# The kit owns its own actor gate too: however the trigger arrived, only the required
	# character can log the read.
	if required_character != "" and str(active_character) != "" \
			and str(active_character) != required_character:
		read_refused.emit("wrong character")
		return
	if _armed_launch_tick >= 0.0:
		read_refused.emit("already armed")
		return
	if _cooldown_until > now:
		read_refused.emit("cooldown")
		return
	var actor := required_character if required_character != "" else str(active_character)
	if float(_gs.get_stat(actor, "stamina")) < _stamina_cost:
		read_refused.emit("stamina")
		return
	var launch_tick := float(basin.call("next_state_tick", _target_state))
	if launch_tick < 0.0:
		read_refused.emit("no window")
		return
	# The prices commit together: the bar debit and the cooldown, then the hold.
	_gs.adjust_stat(actor, "stamina", -_stamina_cost)
	_cooldown_until = now + _cooldown
	_armed_launch_tick = launch_tick
	_armed_ids = _group_ids(actor)
	for i in range(_armed_ids.size()):
		_gs.command_move_to_pos(str(_armed_ids[i]), _lip + LIP_SLOTS[i % LIP_SLOTS.size()])
	sched.cancel_tag(_tag + "_launch")
	sched.schedule_after(maxf(0.0, launch_tick - now) + LAUNCH_SETTLE_DELAY,
		_launch, _tag + "_launch")
	_set_screen_lit(true)
	read_logged.emit(launch_tick)

func _launch() -> void:
	_armed_launch_tick = -1.0
	_set_screen_lit(false)
	if _gs == null:
		return
	var ids := _armed_ids
	_armed_ids = []
	for i in range(ids.size()):
		var id := str(ids[i])
		if _gs.characters.has(id) and not _gs.is_downed(id):
			_gs.command_move_to_pos(id, _dest + DEST_SLOTS[i % DEST_SLOTS.size()])
	crossing_launched.emit()

func _group_ids(actor: String) -> Array:
	var ids: Array = []
	if _group_provider.is_valid():
		var provided: Variant = _group_provider.call()
		if provided is Array:
			ids = (provided as Array).duplicate()
	if ids.is_empty():
		ids = [actor]
	elif not ids.has(actor):
		ids.push_front(actor)
	return ids

func _resolve_basin() -> Variant:
	if not _basin_resolver.is_valid():
		return null
	return _basin_resolver.call(_basin_tag)

func _scheduler_ref():
	if _gs != null and _gs.get("scheduler") != null:
		return _gs.get("scheduler")
	return null

# --- visuals (cosmetic; a pedestal console whose screen lights while a read is armed) ---

var _pedestal: MeshInstance3D = null
var _screen: MeshInstance3D = null

func _build_visual() -> void:
	if _pedestal != null:
		return
	_pedestal = MeshInstance3D.new()
	_pedestal.name = "ConsolePedestal"
	var pm := BoxMesh.new()
	pm.size = Vector3(0.5, 1.0, 0.4)
	_pedestal.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.16, 0.18, 0.2)
	_pedestal.material_override = pmat
	_pedestal.position = Vector3(0.0, 0.5, 0.0)
	add_child(_pedestal)
	_screen = MeshInstance3D.new()
	_screen.name = "ConsoleScreen"
	var sm := BoxMesh.new()
	sm.size = Vector3(0.42, 0.3, 0.06)
	_screen.mesh = sm
	_screen_mat = StandardMaterial3D.new()
	_screen_mat.albedo_color = Color(0.08, 0.12, 0.1)
	_screen_mat.emission_enabled = true
	_screen_mat.emission = Color(0.36, 0.91, 0.5)
	_screen_mat.emission_energy_multiplier = 0.4
	_screen.material_override = _screen_mat
	_screen.position = Vector3(0.0, 1.1, -0.14)
	_screen.rotation_degrees = Vector3(-24.0, 0.0, 0.0)
	add_child(_screen)

func _set_screen_lit(lit: bool) -> void:
	if _screen_mat != null:
		_screen_mat.emission_energy_multiplier = 1.6 if lit else 0.4

func _wire_console_outline() -> void:
	var mgr := OutlineFeedbackManager.ensure(self)
	if mgr == null or _pedestal == null:
		return
	var target := mgr.outline_meshes(self, str(name) + "Outline", [_pedestal, _screen],
		"crossing_assist", maxf(1.0, interaction_radius))
	if target == null:
		return
	if target.has_method("set_interaction_delegate"):
		target.call("set_interaction_delegate", self)
	set_outline_target(target)

func _exit_tree() -> void:
	var sched = _scheduler_ref()
	if sched != null:
		sched.cancel_tag(_tag + "_launch")
