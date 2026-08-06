@tool
class_name StylizedWaterSurface3D
extends MeshInstance3D

## Reusable one-piece water authoring surface.
##
## Give it the interior X/Z size of a basin. The node creates a single
## subdivided PlaneMesh, adds a small coverage margin under the walls, and owns a
## unique ShaderMaterial so state-specific pulses never leak to other water.

const WATER_SHADER := preload("res://resources/stylized_basin_water.gdshader")

@export var surface_size := Vector2(12.0, 9.0):
	set(value):
		surface_size = Vector2(maxf(0.1, value.x), maxf(0.1, value.y))
		_rebuild_mesh()
@export_range(0.0, 1.0, 0.01) var coverage_margin := 0.18:
	set(value):
		coverage_margin = maxf(0.0, value)
		_rebuild_mesh()
@export_range(1, 128, 1) var subdivisions_per_axis := 40:
	set(value):
		subdivisions_per_axis = maxi(1, value)
		_rebuild_mesh()
@export var shallow_color := Color(0.16, 0.62, 0.72, 0.72):
	set(value):
		shallow_color = value
		_sync_material()
@export var deep_color := Color(0.025, 0.15, 0.23, 0.92):
	set(value):
		deep_color = value
		_sync_material()
@export_range(0.0, 0.2, 0.001) var wave_height := 0.055:
	set(value):
		wave_height = maxf(0.0, value)
		_sync_material()
@export_range(0.0, 3.0, 0.01) var flow_speed := 0.32:
	set(value):
		flow_speed = maxf(0.0, value)
		_sync_material()

var _material: ShaderMaterial = null


func _ready() -> void:
	_rebuild_mesh()
	_ensure_material()


func configure(size: Vector2, margin := 0.18) -> void:
	surface_size = size
	coverage_margin = margin
	_rebuild_mesh()
	_ensure_material()


func set_alert_strength(value: float) -> void:
	_ensure_material()
	_material.set_shader_parameter("alert_strength", clampf(value, 0.0, 1.0))


func get_surface_contract() -> Dictionary:
	var plane := mesh as PlaneMesh
	return {
		"contract": "stylized_water_surface/v1",
		"surface_size": [surface_size.x, surface_size.y],
		"covered_size": [plane.size.x, plane.size.y] if plane != null else [],
		"coverage_margin": coverage_margin,
		"subdivisions": [
			plane.subdivide_width if plane != null else 0,
			plane.subdivide_depth if plane != null else 0,
		],
		"single_surface": mesh != null and mesh.get_surface_count() == 1,
		"shader_path": WATER_SHADER.resource_path,
	}


func _rebuild_mesh() -> void:
	var plane := PlaneMesh.new()
	plane.orientation = PlaneMesh.FACE_Y
	plane.size = surface_size + Vector2.ONE * coverage_margin * 2.0
	var longest := maxf(surface_size.x, surface_size.y)
	plane.subdivide_width = maxi(1, int(round(
		float(subdivisions_per_axis) * surface_size.x / longest)))
	plane.subdivide_depth = maxi(1, int(round(
		float(subdivisions_per_axis) * surface_size.y / longest)))
	mesh = plane
	_ensure_material()


func _ensure_material() -> void:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = WATER_SHADER
		# Transparent water must remain legible over the perception overlay.
		_material.render_priority = 127
	material_override = _material
	_sync_material()


func _sync_material() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("shallow_color", shallow_color)
	_material.set_shader_parameter("deep_color", deep_color)
	_material.set_shader_parameter("wave_height", wave_height)
	_material.set_shader_parameter("flow_speed", flow_speed)
