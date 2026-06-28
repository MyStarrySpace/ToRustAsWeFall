class_name Portal
extends Interactable

## A PORTAL: a free, reusable teleport. Click it and the activating member (whoever arrives first) steps through to
## the paired destination — bidirectional (place two pointed at each other) and reusable, so a member can return.
## Only the one who activated it crosses; it never moves the whole party.
##
## Self-contained + reusable like Flure: owns its glow visual, its outline/hover wiring (consistent highlight), and
## its teleport logic. A fragment composes it (place + give it a destination); a level builder will too.

signal stepped_through(who: String, dest: Vector3)

@export var glow_color := Color(0.55, 0.42, 0.98)
@export var glow_radius := 0.5

var _gs   # GameState (Interactable keeps its own _game_state for data binding; we hold our own for the teleport)
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _dest := Vector3.ZERO

## Configure BEFORE adding to the tree. `dest_world` is the paired portal's position this one sends you to.
func configure(gs, world_pos: Vector3, dest_world: Vector3, radius := 1.2,
		color := Color(0.55, 0.42, 0.98)) -> void:
	_gs = gs
	position = world_pos
	_dest = dest_world
	interaction_radius = radius
	glow_color = color
	interactable_type = InteractableType.INSPECTION
	one_shot = false   # reusable: step through, and back
	description = "Step through"
	tutorial_label = "PORTAL"

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

func _on_interacted() -> void:
	step_through()

## Step the activating member (active_character) through to the paired destination.
func step_through() -> bool:
	if _gs == null:
		return false
	var who := str(active_character)
	if who == "" or not _gs.characters.has(who):
		return false
	_gs.command_stop(who)
	var dest := _dest
	if _gs.coord_map != null:
		dest = _gs.coord_map.to_data(_dest)
	_gs.snap_character_to(who, dest)
	stepped_through.emit(who, dest)
	return true
