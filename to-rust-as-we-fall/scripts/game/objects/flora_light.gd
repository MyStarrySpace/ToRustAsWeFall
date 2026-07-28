class_name FloraLight
extends Node3D

## A glowing flora bloom: an emissive sphere + an omni light, as one self-contained node. The shared visual for
## Peris's grown plants — the flora_garden growths (scale + light radius track the growth stage) and contextual
## flora-tending/read lights. A fragment / level builder just places one and, for a growing plant, drives
## its scale + light radius over time (set_growth_scale / set_light_range). Cosmetic only: the gameplay read lives
## in GameState; this is the light you see.
##
## Self-contained + reusable like Flure/PortalPad/Capbage/Channel: configure() BEFORE add_child, then _ready builds
## the mesh + light from the configured look. Defaults match the flora_garden bloom; override via configure(opts).

@export var albedo := Color(0.35, 0.8, 0.5)
@export var emission := Color(0.36, 0.91, 0.5)
@export var emission_energy := 1.6
@export var bloom_radius := 0.18
@export var light_color := Color(0.5, 1.0, 0.65)
@export var light_energy := 0.8
@export var light_range := 0.5
@export var mesh_offset_y := 0.25
@export var light_offset_y := 0.6

var _mesh: MeshInstance3D
var _light: OmniLight3D

## Apply look overrides BEFORE adding to the tree. Any key omitted keeps its (@export) default. Keys:
## albedo, emission, emission_energy, bloom_radius, light_color, light_energy, light_range, mesh_offset_y,
## light_offset_y.
func configure(opts: Dictionary = {}) -> void:
	albedo = opts.get("albedo", albedo)
	emission = opts.get("emission", emission)
	emission_energy = opts.get("emission_energy", emission_energy)
	bloom_radius = opts.get("bloom_radius", bloom_radius)
	light_color = opts.get("light_color", light_color)
	light_energy = opts.get("light_energy", light_energy)
	light_range = opts.get("light_range", light_range)
	mesh_offset_y = opts.get("mesh_offset_y", mesh_offset_y)
	light_offset_y = opts.get("light_offset_y", light_offset_y)

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "Bloom"
	var sph := SphereMesh.new()
	sph.radius = bloom_radius
	sph.height = bloom_radius * 2.0
	_mesh.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = emission_energy
	_mesh.material_override = mat
	_mesh.position = Vector3(0.0, mesh_offset_y, 0.0)
	add_child(_mesh)
	_light = OmniLight3D.new()
	_light.name = "Glow"
	_light.light_color = light_color
	_light.light_energy = light_energy
	_light.omni_range = light_range
	_light.position = Vector3(0.0, light_offset_y, 0.0)
	add_child(_light)

## Scale the bloom mesh (a growing plant gets bigger with its stage). Safe before _ready (applied on build via scale).
func set_growth_scale(s: float) -> void:
	if _mesh != null:
		_mesh.scale = Vector3.ONE * s

## Set the omni light's reach (flora_garden drives this from GameState's flora light radius).
func set_light_range(r: float) -> void:
	if _light != null:
		_light.omni_range = r
