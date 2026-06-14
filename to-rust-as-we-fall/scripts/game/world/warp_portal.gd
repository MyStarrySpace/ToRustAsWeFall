class_name WarpPortal
extends Node3D

## A one-shot portal / teleport-in VFX: a ground ring flashes open, a vertical energy column pulses,
## and sparks rise from the spot. Purely COSMETIC (tween + particle driven) — instantiate it at a
## position, call play(), and it animates then self-frees. No game state, so it never touches
## determinism; a scene drops one in when a character should warp in.

const GREEN := Color(0.36, 0.91, 0.5)

## Animate the portal in the given colour. Builds the ring + column + sparks, runs the flash, and
## queue_frees once the effect and its tail have finished.
func play(glow: Color = GREEN, duration: float = 1.4) -> void:
	_ring(glow, duration)
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

## Flat ground ring that snaps open and fades — the portal's mouth on the floor.
func _ring(glow: Color, duration: float) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.64
	ring.mesh = torus
	ring.rotation.x = -PI / 2.0  # lay the torus flat on the floor
	ring.position.y = 0.06
	var mat := _glow_mat(glow)
	ring.material_override = mat
	add_child(ring)
	ring.scale = Vector3(0.15, 0.15, 0.15)
	var t := create_tween()
	t.tween_property(ring, "scale", Vector3(1.8, 1.8, 1.8), duration * 0.7) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(mat, "albedo_color:a", 0.0, duration * 0.85).set_delay(duration * 0.2)

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
