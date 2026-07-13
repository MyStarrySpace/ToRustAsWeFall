class_name Hushbloom
extends Interactable

## HUSHBLOOM (flora_taxonomy): a small nodding flower holding neuroactive compounds — thigmonastic:
## ANY body entering its trigger radius makes it release a STUN BURST (canon: "fires on ANY body",
## so the counterplay is LEADING a pursuer across it). The burst freezes enemies (Enemy.stun) and
## SEALS portals (PortalPad.stun) in its radius — the portal-stun is the chase framework's
## expert-solution mechanic. After a release the core is visibly empty and regenerates over time;
## a charged bloom can be PICKED (click) and carried for a thrown burst (the chunk owns the throw).
## Self-contained like Flure: owns its visual, its proximity poll (scheduler cadence — never
## per-frame), and its burst; the loader injects game state + enemy/portal providers.

signal burst_fired(at: Vector3)
signal picked()

@export var trigger_radius := 1.5
@export var stun_radius := 3.4
@export var stun_secs := 6.0
@export var regen_secs := 90.0
@export var pickable := true

const POLL := 0.25

var _gs
var _charged := true
var _enemy_provider: Callable = Callable()
var _portal_provider: Callable = Callable()
var _petal_mat: StandardMaterial3D

func configure(gs, world_pos: Vector3, opts: Dictionary = {}) -> void:
	_gs = gs
	position = world_pos
	trigger_radius = float(opts.get("trigger_radius", trigger_radius))
	stun_radius = float(opts.get("stun_radius", stun_radius))
	stun_secs = float(opts.get("stun_secs", stun_secs))
	regen_secs = float(opts.get("regen_secs", regen_secs))
	pickable = bool(opts.get("pickable", pickable))
	interaction_radius = 1.1
	interactable_type = InteractableType.INSPECTION
	one_shot = true
	description = "Take the charged hushbloom"
	tutorial_label = "TAKE"
	interaction_enabled = pickable

## Providers: callables returning the live enemy nodes / PortalPads the burst may reach.
func set_enemy_provider(cb: Callable) -> void:
	_enemy_provider = cb

func set_portal_provider(cb: Callable) -> void:
	_portal_provider = cb

func _ready() -> void:
	if get_node_or_null("CollisionShape3D") == null:
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		var sh := SphereShape3D.new()
		sh.radius = interaction_radius
		cs.shape = sh
		add_child(cs)
	_build_visual()
	super._ready()
	if not pickable:
		set_interaction_enabled(false)
	if not interacted.is_connected(_on_picked):
		interacted.connect(_on_picked)
	_arm_poll()

func _build_visual() -> void:
	var stem := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.02
	cyl.bottom_radius = 0.035
	cyl.height = 0.5
	stem.mesh = cyl
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.32, 0.42, 0.3)
	stem.material_override = sm
	stem.position = Vector3(0, 0.25, 0)
	add_child(stem)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.13
	sph.height = 0.22
	head.mesh = sph
	_petal_mat = StandardMaterial3D.new()
	_petal_mat.albedo_color = Color(0.78, 0.72, 0.88)
	_petal_mat.emission_enabled = true
	_petal_mat.emission = Color(0.82, 0.74, 0.95)
	_petal_mat.emission_energy_multiplier = 0.5
	head.material_override = _petal_mat
	head.position = Vector3(0.04, 0.54, 0.0)
	add_child(head)

func _sched():
	return _gs.scheduler if _gs != null else null

func _poll_tag() -> String:
	return "hush_%d" % get_instance_id()

func _arm_poll() -> void:
	var sched = _sched()
	if sched == null:
		return
	sched.cancel_tag(_poll_tag())
	sched.schedule_after(POLL, _proximity_poll, _poll_tag())

func _proximity_poll() -> void:
	if _charged and _gs != null and is_visible_in_tree():
		for id_v in _gs.characters.keys():
			var p: Vector3 = _gs.get_position(str(id_v))
			if Vector2(p.x - global_position.x, p.z - global_position.z).length() <= trigger_radius:
				burst()
				break
	_arm_poll()

## Release the stun: freeze every enemy and seal every portal within stun_radius. One shot per
## charge; the core regenerates on the scheduler.
func burst() -> bool:
	if not _charged:
		return false
	_charged = false
	set_interaction_enabled(false)
	if _petal_mat != null:
		_petal_mat.emission_energy_multiplier = 0.05
		_petal_mat.albedo_color = Color(0.6, 0.6, 0.62)
	Hushbloom.burst_at(global_position, _list(_enemy_provider), _list(_portal_provider),
		stun_radius, stun_secs)
	burst_fired.emit(global_position)
	var sched = _sched()
	if sched != null and regen_secs > 0.0:
		sched.schedule_after(regen_secs, _recharge, _poll_tag() + "_regen")
	return true

## The shared burst resolution — also the THROWN use (a carried bloom bursting at a target point;
## the chunk that owns the carry calls this directly).
static func burst_at(pos: Vector3, enemies: Array, portals: Array, radius: float, secs: float) -> void:
	for e in enemies:
		if e == null or not is_instance_valid(e) or not e.has_method("stun"):
			continue
		# the DATA position is the truth (enemy nodes only sync per-frame — stale headless)
		var ep: Vector3 = (e as Node3D).global_position
		if "game_state" in e and e.game_state != null and "char_id" in e 				and e.game_state.characters.has(e.char_id):
			ep = e.game_state.get_position(e.char_id)
		if Vector2(ep.x - pos.x, ep.z - pos.z).length() <= radius:
			e.stun(secs)
	for pad in portals:
		if pad == null or not is_instance_valid(pad) or not pad.has_method("stun"):
			continue
		var pp: Vector3 = (pad as Node3D).global_position
		if Vector2(pp.x - pos.x, pp.z - pos.z).length() <= radius:
			pad.stun(secs)

func _list(provider: Callable) -> Array:
	if provider.is_valid():
		var out = provider.call()
		if out is Array:
			return out
	return []

func _recharge() -> void:
	_charged = true
	if _petal_mat != null:
		_petal_mat.emission_energy_multiplier = 0.5
		_petal_mat.albedo_color = Color(0.78, 0.72, 0.88)
	if pickable:
		reset()

func is_charged() -> bool:
	return _charged

## Pick the charged bloom (the carry verb): the plant leaves the world; the caller banks the item.
func pick() -> bool:
	if not _charged:
		return false
	_charged = false
	var sched = _sched()
	if sched != null:
		sched.cancel_tag(_poll_tag())
		sched.cancel_tag(_poll_tag() + "_regen")
	visible = false
	set_interaction_enabled(false)
	picked.emit()
	return true

func _on_picked() -> void:
	pick()
