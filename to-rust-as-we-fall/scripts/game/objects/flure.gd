class_name Flure
extends Interactable

## A LURE flower (channels "flure"). Activating it emits a signal the hunters home in on: every lure target within
## attract_range drops the hunt, is marked DISTRACTED, and is sent to the flure — crossing the channels en route,
## where the Channel drowns them. attract_range is deliberately LARGER than the hunters' player-sense range, so they
## lock onto the flure rather than the party (they don't immediately come across at you).
##
## Self-contained + reusable: it owns its glow visual, its outline/hover wiring (so EVERY flure in EVERY fragment is
## highlighted identically — no per-chunk variance), and its lure logic. A fragment / level builder just places it
## and injects (game_state, the lure-target ids). This is the first of the modular gameplay objects: a fragment
## becomes a COMPOSITION of these, not a script that re-implements each mechanic.

signal flure_activated(pulled: int)

@export var attract_range := 32.0
@export var glow_color := Color(0.95, 0.78, 0.2)
@export var glow_radius := 0.45

## Optional park point for lured FSM enemies (INF = the flure itself) + how long the song holds.
var settle_pos := Vector3.INF
var lure_duration := 60.0

var _active := false
var _enemy_resolver: Callable = Callable()   # id -> Enemy node; the loader installs it
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _lure_target_ids: Array = []
var _gs   # the GameState (Interactable keeps its own _game_state for data binding; we hold our own for the lure)

## Configure BEFORE adding to the tree (interaction_radius is read by Interactable._ready when it sizes the pick
## shape). game_state + the lure targets are the only injected dependencies.
func configure(gs, world_pos: Vector3, lure_target_ids: Array, attract := 32.0, radius := 1.6,
		color := Color(0.95, 0.78, 0.2)) -> void:
	_gs = gs
	position = world_pos
	attract_range = attract
	interaction_radius = radius
	glow_color = color
	interactable_type = InteractableType.INSPECTION
	one_shot = true
	description = "Light the flure"
	tutorial_label = "FLURE"
	_lure_target_ids = lure_target_ids.duplicate()

func _ready() -> void:
	# Interactable normally gets its pick shape from interactable.tscn; a code-spawned object self-builds it (and
	# the glow visual) BEFORE Interactable._ready reads the shape + sizes it to interaction_radius.
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
	_glow_mat.emission_energy_multiplier = 0.5
	mi.material_override = _glow_mat
	mi.position = Vector3(0.0, 0.35, 0.0)
	add_child(mi)
	return mi

## Wire the SHARED outline/hover system onto the glow mesh (hover = white hull, SHIFT = reveal, click = the queued
## glow), the same path every interactable uses — so the object carries its own consistent feedback.
func _wire_outline() -> void:
	var mgr := OutlineFeedbackManager.ensure(self)
	if mgr == null or _glow == null:
		return
	var target := mgr.outline_meshes(self, str(name) + "Outline", [_glow], "flure", maxf(1.0, interaction_radius))
	if target == null:
		return
	if target is Node3D and _glow is Node3D:
		(target as Node3D).global_position = (_glow as Node3D).global_position
	if target.has_method("set_interaction_delegate"):
		target.call("set_interaction_delegate", self)
	set_outline_target(target)

func _on_interacted() -> void:
	activate()

## Light the flure: pull every lure target within attract_range toward it (distracted + moved). Returns true if it
## pulled anyone. Idempotent (a re-light is a no-op once active) — clear with reset_flure().
func activate() -> bool:
	if _active or _gs == null:
		return false
	_active = true
	if _glow_mat != null:
		_glow_mat.emission_energy_multiplier = 3.0
	var flat := global_position
	if _gs.coord_map != null:
		flat = _gs.coord_map.to_data(global_position)
	var pulled := 0
	for tid in _lure_target_ids:
		if not _gs.characters.has(tid):
			continue
		if _gs.get_position(tid).distance_to(flat) > attract_range:
			continue
		var enemy_node = _enemy_resolver.call(tid) if _enemy_resolver.is_valid() else null
		if enemy_node != null and is_instance_valid(enemy_node) and enemy_node.has_method("lure_to"):
			var park := settle_pos if settle_pos != Vector3.INF else flat
			enemy_node.lure_to(park, lure_duration)
		else:
			_gs.set_character_distracted(tid, true)
			_gs.command_move_to_pos(tid, flat)
		pulled += 1
	# A re-tendable flure re-arms itself when the song ends (scheduler-driven, derived on replay).
	if not one_shot and _gs.scheduler != null:
		_gs.scheduler.cancel_tag("flure_reset_" + str(name))
		_gs.scheduler.schedule_after(lure_duration, reset_flure, "flure_reset_" + str(name))
	flure_activated.emit(pulled)
	return pulled > 0

## The loader hands the flure a way to find the Enemy NODE behind a lure-target id, so an FSM enemy
## is lured through its own `lured` state (walk to settle, park distracted, walk home) instead of a
## raw data-layer move its state machine would fight.
func set_enemy_resolver(resolver: Callable) -> void:
	_enemy_resolver = resolver

func is_active() -> bool:
	return _active

func reset_flure() -> void:
	_active = false
	if _glow_mat != null:
		_glow_mat.emission_energy_multiplier = 0.5
