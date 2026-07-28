class_name Sapscrap
extends Enemy

## Iron-seeking swarm body used in the Open Files transfer bay.
##
## The shared Enemy FSM owns movement, detection, attack, lure, save/load, and replay authority.
## This subclass fixes the Sapscrap's gameplay tuning and attaches the portable placeholder model;
## the Open Files iron-purge receiver supplies the species-specific environmental counter.

const BiotaPlaceholderCatalogScript := preload(
	"res://scripts/game/objects/biota_placeholder_catalog.gd")
const VISUAL_KEY := "fauna/sapscrap"

var _visual_root: Node3D


func _ready() -> void:
	display_name = "Sapscrap"
	color = Color(0.48, 0.24, 0.10)
	emp_compatible = false
	max_hp = 16.0
	move_speed = 3.35
	pursuit_speed = 4.35
	detection_range = 6.4
	attack_range = 2.1
	windup_duration = 0.58
	charge_speed = 7.2
	charge_damage = 11.0
	recover_duration = 0.9
	super._ready()


func _build_visual() -> void:
	_visual_root = BiotaPlaceholderCatalogScript.instantiate(VISUAL_KEY)
	if _visual_root == null:
		super._build_visual()
		return
	_visual_root.name = "SapscrapVisual"
	_visual_root.position = Vector3(0.0, 0.10, 0.0)
	_visual_root.scale = Vector3.ONE * 0.82
	add_child(_visual_root)
	_mesh = _visual_root.get_node_or_null("Body") as MeshInstance3D
	if _mesh != null:
		_mesh.layers = 2
	var signal_mesh := _visual_root.get_node_or_null("Signal") as MeshInstance3D
	if signal_mesh != null:
		signal_mesh.layers = 2
