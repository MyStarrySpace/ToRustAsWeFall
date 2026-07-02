class_name CandidZone
extends Node3D

## CANDID BIOFILM GROUND (fauna_roster: Candids are a TERRAIN floor hazard): a pale mat whose
## chemistry BLINDS enforcement scans — anyone standing in it is fully unreadable (CONCEAL_FULL) —
## and whose acids drain hp the whole time (the DoT floor). The risk inversion the ecology register
## names: the poison floor IS the safe corridor past a Naturalizer patrol; you trade hp for
## invisibility and budget the crossing in health instead of stamina.
##
## Terrain-side realization of the species (the creature behaviors come later; ECOLOGY_COMBOS Card 2).
## Self-contained like Scarpet: owns its mat visual and its coverage test; the LOADER's shared
## concealment pass and DoT tick read it — no per-chunk hide or damage logic.

@export var mat_color := Color(0.82, 0.80, 0.72)
@export var mat_emission := Color(0.75, 0.72, 0.6)
@export var half_size := Vector2(3.0, 3.0)   # world-XZ half extents of the mat
@export var dot_per_sec := 4.0               # hp drain while standing in it
@export var show_label := true

var _mat: MeshInstance3D

func configure(world_pos: Vector3, half_extents: Vector2, dot := 4.0, with_label := true) -> void:
	position = world_pos
	half_size = half_extents
	dot_per_sec = dot
	show_label = with_label

func _ready() -> void:
	_mat = MeshInstance3D.new()
	_mat.name = "Mat"
	var bm := BoxMesh.new()
	bm.size = Vector3(half_size.x * 2.0, 0.05, half_size.y * 2.0)
	_mat.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = mat_color
	m.emission_enabled = true
	m.emission = mat_emission
	m.emission_energy_multiplier = 0.18
	_mat.material_override = m
	_mat.position = Vector3(0.0, 0.025, 0.0)
	add_child(_mat)
	if show_label:
		var lbl := Label3D.new()
		lbl.text = "biofilm"
		lbl.font_size = 40
		lbl.modulate = Color(0.85, 0.82, 0.7)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = Vector3(0.0, 0.9, 0.0)
		add_child(lbl)

## True if `world_pos` stands on the mat (scan-blind + draining).
func covers(world_pos: Vector3) -> bool:
	return absf(world_pos.x - global_position.x) <= half_size.x \
		and absf(world_pos.z - global_position.z) <= half_size.y
