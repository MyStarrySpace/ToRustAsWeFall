class_name WarpPortal
extends Node3D

## A one-shot portal / teleport-in VFX: a ground ring flashes open, a vertical energy column pulses,
## and sparks rise from the spot. Purely COSMETIC (tween + particle driven) — instantiate it at a
## position, call play(), and it animates then self-frees. No game state, so it never touches
## determinism; a scene drops one in when a character should warp in.

const GREEN := Color(0.36, 0.91, 0.5)
const PORTAL_DITHER_SHADER := preload("res://resources/portal_dither.gdshader")

## Animate the portal in the given colour. Builds the dithering ground ring + column + sparks, runs
## the flash, and queue_frees once the effect and its tail have finished.
func play(glow: Color = GREEN, duration: float = 1.4) -> void:
	_dither_ring(glow, duration)
	_column(glow, duration)
	_sparks(glow)
	var life := create_tween()
	life.tween_interval(duration + 1.4)
	life.tween_callback(queue_free)

func _glow_mat(glow: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD  # additive: reads as light in the dark room
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = glow
	m.emission_enabled = true
	m.emission = glow
	m.emission_energy_multiplier = 3.0
	return m

## The portal's mouth on the floor: a flat 2D quad whose ring shape DITHERS in, then stipples away —
## the same ordered-Bayer dither as the hover grid. A PlaneMesh lies flat on the ground by default, so
## there's no orientation to get wrong (the old torus ring stood the wrong way).
func _dither_ring(glow: Color, duration: float) -> void:
	var quad := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3.4, 3.4)  # ground footprint the ring sits inside
	quad.mesh = plane
	quad.position.y = 0.06
	var mat := ShaderMaterial.new()
	mat.shader = PORTAL_DITHER_SHADER
	mat.set_shader_parameter("color", glow)
	mat.set_shader_parameter("dissolve", 0.0)
	quad.material_override = mat
	add_child(quad)
	# Dither IN fast (the ring resolves), then dither OUT over the rest of the beat.
	var t := create_tween()
	t.tween_method(func(v): mat.set_shader_parameter("dissolve", v), 0.0, 1.1, duration * 0.28) \
		.set_ease(Tween.EASE_OUT)
	t.tween_method(func(v): mat.set_shader_parameter("dissolve", v), 1.1, 0.0, duration * 0.72) \
		.set_ease(Tween.EASE_IN)

## Vertical energy column that flashes up and dies back — the beam the body forms inside.
func _column(glow: Color, duration: float) -> void:
	var col := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.34
	cyl.bottom_radius = 0.48
	cyl.height = 2.6
	col.mesh = cyl
	col.position.y = 1.3
	var mat := _glow_mat(glow)
	mat.albedo_color.a = 0.0
	col.material_override = mat
	add_child(col)
	col.scale = Vector3(0.25, 1.0, 0.25)
	var t := create_tween()
	t.tween_property(mat, "albedo_color:a", 0.7, duration * 0.22)
	t.parallel().tween_property(col, "scale", Vector3(1.0, 1.0, 1.0), duration * 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(mat, "albedo_color:a", 0.0, duration * 0.65)

## A one-shot upward spray of energy sparks rising out of the ring.
func _sparks(glow: Color) -> void:
	var p := GPUParticles3D.new()
	p.amount = 48
	p.lifetime = 1.1
	p.one_shot = true
	p.explosiveness = 0.55
	p.position.y = 0.1
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3(0, 1, 0)
	pm.emission_ring_radius = 0.55
	pm.emission_ring_inner_radius = 0.3
	pm.emission_ring_height = 0.05
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 18.0
	pm.initial_velocity_min = 1.6
	pm.initial_velocity_max = 3.2
	pm.gravity = Vector3(0, -2.0, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.color = glow
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	var qmat := _glow_mat(glow)
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = qmat
	p.draw_pass_1 = quad
	add_child(p)
	p.restart()
