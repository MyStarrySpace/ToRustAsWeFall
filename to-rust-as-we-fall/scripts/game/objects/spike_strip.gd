class_name SpikeStrip
extends Node3D

## ANTI-LOITER SPIKE STRIP (hostile architecture — Cleanstreets canon, SET_PIECES 21): a curb of
## ground studs installed to make standing still cost something. Mechanically a symmetric damage
## floor: ANY character on it drains hp — party members crossing pay, and an enemy lured, pushed,
## or routed across it takes the same drain. That symmetry is the design read (hostile
## architecture is indiscriminate) AND the tactic: the ecology verbs that move enemies (Flure
## lures, pushes, patrol routing) turn the city's cruelty into a weapon.
##
## Self-contained like CandidZone: owns its curb + spike visuals and its coverage test; the
## LOADER's shared DoT tick reads covers() and applies the drain — no per-chunk damage logic.
## No concealment, no slow: it only hurts.

@export var half_size := Vector2(2.0, 0.6)   # world-XZ half extents (a strip: long and narrow)
@export var dot_per_sec := 6.0               # hp drain while standing on it
@export var show_label := true

func configure(world_pos: Vector3, half_extents: Vector2, dot := 6.0, with_label := true) -> void:
	position = world_pos
	half_size = half_extents
	dot_per_sec = dot
	show_label = with_label

func _ready() -> void:
	var curb := MeshInstance3D.new()
	curb.name = "Curb"
	var bm := BoxMesh.new()
	bm.size = Vector3(half_size.x * 2.0, 0.1, half_size.y * 2.0)
	curb.mesh = bm
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.42, 0.42, 0.44)
	cm.roughness = 0.9
	curb.material_override = cm
	curb.position = Vector3(0.0, 0.05, 0.0)
	add_child(curb)
	# Stud rows: small metal cones pitched along the strip.
	var stud_mat := StandardMaterial3D.new()
	stud_mat.albedo_color = Color(0.68, 0.7, 0.74)
	stud_mat.metallic = 0.8
	stud_mat.roughness = 0.35
	var cols := maxi(2, int(half_size.x / 0.35))
	var rows := maxi(1, int(half_size.y / 0.35))
	for ix in cols:
		for iz in rows:
			var spike := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.05
			cone.height = 0.16
			spike.mesh = cone
			spike.material_override = stud_mat
			spike.position = Vector3(
				(float(ix) + 0.5) / float(cols) * half_size.x * 2.0 - half_size.x,
				0.18,
				(float(iz) + 0.5) / float(rows) * half_size.y * 2.0 - half_size.y)
			add_child(spike)
	if show_label:
		var lbl := Label3D.new()
		lbl.text = "anti-loiter studs"
		lbl.font_size = 36
		lbl.modulate = Color(0.75, 0.75, 0.78)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = Vector3(0.0, 0.9, 0.0)
		add_child(lbl)

## True if `world_pos` stands on the studs (draining — party and enemy alike).
func covers(world_pos: Vector3) -> bool:
	return absf(world_pos.x - global_position.x) <= half_size.x \
		and absf(world_pos.z - global_position.z) <= half_size.y
