class_name Scarpet
extends Node3D

const BiotaPlaceholderCatalogScript := preload(
	"res://scripts/game/objects/biota_placeholder_catalog.gd")
const VISUAL_KEY := "flora/scarpet"
const REFERENCE_CONCEAL_RADIUS := 1.65

## SCARPET (canonical medium-hide flora): a low mat growth a member stands on for a PARTIAL hide.
## Concealment is POSITIONAL and MEDIUM-tier: an outer-range pass misses a member on the mat, a close
## pass does not (GameState CONCEAL_MEDIUM semantics — the tier teach). Not an interactable: you stand
## on it, you don't click it; the pad visual + label advertise it.
##
## Self-contained + reusable like Flure/Capbage/PortalPad: owns its pad visual and its hide test. A
## fragment composes it; the LOADER's shared concealment pass asks conceals(pos) each frame — no
## per-chunk hide logic.

@export var pad_color := Color(0.12, 0.22, 0.14)
@export var pad_emission := Color(0.3, 0.55, 0.35)
@export var conceal_radius := 1.65
@export var show_label := true

var _pad: MeshInstance3D
var _visual_root: Node3D
var _concealment_origin := Vector3.INF

func configure(world_pos: Vector3, radius := 1.65, with_label := true) -> void:
	position = world_pos
	conceal_radius = radius
	show_label = with_label

func _ready() -> void:
	_build_visual()
	if show_label:
		var lbl := Label3D.new()
		lbl.text = "scarpet"
		lbl.font_size = 40
		lbl.modulate = Color(0.45, 0.75, 0.5)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = Vector3(0.0, 0.9, 0.0)
		add_child(lbl)


func _build_visual() -> void:
	_visual_root = BiotaPlaceholderCatalogScript.instantiate(VISUAL_KEY)
	if _visual_root == null:
		push_error("Scarpet could not instantiate its portable biota presenter")
		return
	_visual_root.name = "ScarpetVisual"
	var footprint_scale := maxf(0.01, conceal_radius / REFERENCE_CONCEAL_RADIUS)
	# Concealment is planar. Preserve the authored plant height while making a larger
	# gameplay patch visibly occupy a proportionally larger XZ footprint.
	_visual_root.scale = Vector3(footprint_scale, 1.0, footprint_scale)
	_visual_root.set_meta("gameplay_visual_key", VISUAL_KEY)
	add_child(_visual_root)
	_pad = _visual_root.get_node_or_null("Body") as MeshInstance3D
	if _pad == null:
		push_error("Scarpet portable presenter is missing its Body mesh")


func get_visual_presenter() -> Node3D:
	return _visual_root

## True if `world_pos` is on this mat (a member there is CONCEAL_MEDIUM unless something stronger holds).
func conceals(world_pos: Vector3) -> bool:
	var origin := global_position if _concealment_origin == Vector3.INF else _concealment_origin
	return Vector2(world_pos.x - origin.x, world_pos.z - origin.z).length() <= conceal_radius


func get_concealment_origin() -> Vector3:
	return global_position if _concealment_origin == Vector3.INF else _concealment_origin


## Coordinate-map presenters call this before moving the visible root. Ordinary
## authored scenes retain the original global-position behavior.
func set_concealment_origin(origin: Vector3) -> void:
	_concealment_origin = origin
