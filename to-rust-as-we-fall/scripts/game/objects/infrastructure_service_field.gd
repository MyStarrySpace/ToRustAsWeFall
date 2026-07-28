class_name InfrastructureServiceField
extends Node3D

## A service operation's environmental consequence. Before the receiving plant is commissioned this
## marks a concrete local cost (arc, spill, steam, or scanner exposure); afterwards the SAME patch is
## visibly safe. The fragment loader owns damage/concealment polling, just as it does for CandidZone and
## SpikeStrip, while this reusable object owns the state transition and its legible world feedback.

signal field_resolved(field: InfrastructureServiceField)

@export var half_size := Vector2(1.15, 0.7)
@export var dot_per_sec := 0.0
@export var safe_concealment := false

var commodity := "service"
var hazard_label := "SERVICE FAULT"
var safe_label := "SERVICE BAY SAFE"
var _resolved := false
var _surface: MeshInstance3D
var _surface_material: StandardMaterial3D
var _status_label: Label3D


func configure(spec: Dictionary) -> void:
	position = spec.get("position", Vector3.ZERO) as Vector3
	commodity = str(spec.get("commodity", "service"))
	var half_v: Variant = spec.get("half", Vector2(1.15, 0.7))
	half_size = half_v as Vector2 if half_v is Vector2 else Vector2(1.15, 0.7)
	dot_per_sec = maxf(0.0, float(spec.get("damage_per_second", 0.0)))
	safe_concealment = bool(spec.get("safe_concealment", false))
	hazard_label = str(spec.get("hazard_label", "SERVICE FAULT"))
	safe_label = str(spec.get("safe_label", "SERVICE BAY SAFE"))


func _ready() -> void:
	_surface = MeshInstance3D.new()
	_surface.name = "ServiceFieldSurface"
	var box := BoxMesh.new()
	box.size = Vector3(half_size.x * 2.0, 0.07, half_size.y * 2.0)
	_surface.mesh = box
	_surface.position = Vector3(0.0, 0.045, 0.0)
	_surface_material = StandardMaterial3D.new()
	_surface_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_surface_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_surface.material_override = _surface_material
	add_child(_surface)

	# Four low corner beacons make the coverage readable from an oblique camera. They are state
	# visualization, not the authored building asset, and deliberately stay cheap/runtime-driven.
	for x_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			var beacon := MeshInstance3D.new()
			beacon.name = "FieldBeacon"
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.055
			cylinder.bottom_radius = 0.08
			cylinder.height = 0.28
			beacon.mesh = cylinder
			beacon.material_override = _surface_material
			beacon.position = Vector3(x_sign * half_size.x, 0.14, z_sign * half_size.y)
			add_child(beacon)

	_status_label = Label3D.new()
	_status_label.name = "ServiceFieldStatus"
	_status_label.font_size = 32
	_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_label.no_depth_test = true
	_status_label.position = Vector3(0.0, 0.72, 0.0)
	add_child(_status_label)
	_apply_visual_state()


func covers(world_position: Vector3) -> bool:
	return absf(world_position.x - global_position.x) <= half_size.x \
		and absf(world_position.z - global_position.z) <= half_size.y


func is_hazardous() -> bool:
	return not _resolved and dot_per_sec > 0.0


func conceals(world_position: Vector3) -> bool:
	return _resolved and safe_concealment and covers(world_position)


func resolve_field() -> bool:
	if _resolved:
		return false
	_resolved = true
	_apply_visual_state()
	field_resolved.emit(self)
	return true


func reset_field() -> void:
	_resolved = false
	_apply_visual_state()


## Restore-only presenter seam owned by InfrastructureOperation. Unlike resolve_field(), this mirrors
## portable truth without announcing a new consequence; loading a completed operation must not fire the
## gameplay signal a second time.
func restore_resolved_state(resolved: bool) -> void:
	_resolved = resolved
	_apply_visual_state()


func get_state() -> Dictionary:
	return {
		"commodity": commodity,
		"resolved": _resolved,
		"hazardous": is_hazardous(),
		"safe_concealment": safe_concealment,
		"damage_per_second": dot_per_sec,
	}


func _apply_visual_state() -> void:
	if _surface_material == null or _status_label == null:
		return
	var tint := Color(0.24, 0.92, 0.58, 0.42) if _resolved else Color(1.0, 0.30, 0.12, 0.58)
	if not _resolved and dot_per_sec <= 0.0:
		tint = Color(0.96, 0.72, 0.18, 0.52)
	_surface_material.albedo_color = tint
	_surface_material.emission_enabled = true
	_surface_material.emission = Color(tint.r, tint.g, tint.b, 1.0)
	_surface_material.emission_energy_multiplier = 1.35 if _resolved else 1.75
	_status_label.text = safe_label if _resolved else (
		"%s // %.1f HP/s" % [hazard_label, dot_per_sec] if dot_per_sec > 0.0 else hazard_label
	)
	_status_label.modulate = Color(tint.r, tint.g, tint.b, 1.0)
