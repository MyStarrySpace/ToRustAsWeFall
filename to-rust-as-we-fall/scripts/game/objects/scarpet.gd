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
var _rig: FloraRig = null
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


## The modelled carpet where one is available, the portable presenter otherwise.
##
## The rigged body is the one that can GROW: the spec makes the expanding patch
## boundary the read on tending progress ("the visible expansion of the patch
## boundary tells the player when work is paying off"), which is a single patch
## bone scaling the mat and the tufts riding it. The clip is authored and ships;
## the plant plays it when something tends it.
func _build_visual() -> void:
	var footprint_scale := maxf(0.01, conceal_radius / REFERENCE_CONCEAL_RADIUS)
	if FloraRig.has_rig("scarpet"):
		var rigged := FloraRig.new()
		rigged.name = "ScarpetVisual"
		add_child(rigged)
		if rigged.setup("scarpet"):
			_rig = rigged
			_visual_root = rigged
			# Concealment is planar, so a larger gameplay patch spreads across
			# more ground without growing taller.
			rigged.scale = Vector3(footprint_scale, 1.0, footprint_scale)
			rigged.set_meta("gameplay_visual_key", VISUAL_KEY)
			return
		rigged.queue_free()
	_visual_root = BiotaPlaceholderCatalogScript.instantiate(VISUAL_KEY)
	if _visual_root == null:
		push_error("Scarpet could not instantiate its portable biota presenter")
		return
	_visual_root.name = "ScarpetVisual"
	_visual_root.scale = Vector3(footprint_scale, 1.0, footprint_scale)
	_visual_root.set_meta("gameplay_visual_key", VISUAL_KEY)
	add_child(_visual_root)
	_pad = _visual_root.get_node_or_null("Body") as MeshInstance3D
	if _pad == null:
		push_error("Scarpet portable presenter is missing its Body mesh")


## Work the patch: the moss spreads outward and flashes when the growth stops.
## Cosmetic only — the caller owns how long tending takes and whether it counted.
func tend() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.play("scarpet_tend")


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
