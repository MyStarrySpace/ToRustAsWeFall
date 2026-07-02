class_name Scarpet
extends Node3D

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

func configure(world_pos: Vector3, radius := 1.65, with_label := true) -> void:
	position = world_pos
	conceal_radius = radius
	show_label = with_label

func _ready() -> void:
	_pad = MeshInstance3D.new()
	_pad.name = "Pad"
	var bm := BoxMesh.new()
	bm.size = Vector3(conceal_radius * 1.3, 0.04, conceal_radius * 1.3)
	_pad.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = pad_color
	m.emission_enabled = true
	m.emission = pad_emission
	m.emission_energy_multiplier = 0.2
	_pad.material_override = m
	_pad.position = Vector3(0.0, 0.02, 0.0)
	add_child(_pad)
	if show_label:
		var lbl := Label3D.new()
		lbl.text = "scarpet"
		lbl.font_size = 40
		lbl.modulate = Color(0.45, 0.75, 0.5)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = Vector3(0.0, 0.9, 0.0)
		add_child(lbl)

## True if `world_pos` is on this mat (a member there is CONCEAL_MEDIUM unless something stronger holds).
func conceals(world_pos: Vector3) -> bool:
	return Vector2(world_pos.x - global_position.x, world_pos.z - global_position.z).length() <= conceal_radius
