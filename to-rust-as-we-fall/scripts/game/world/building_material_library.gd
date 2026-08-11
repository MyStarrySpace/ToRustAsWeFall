class_name BuildingMaterialLibrary
extends RefCounted

## The surface library the procedurally-drawn architecture wears.
##
## The buildings are built in GDScript, and every face on them used to be a flat
## albedo colour — there was nowhere for an artist to put a brush. The materials
## now live as ordinary PNG tiles under `resources/materials/building/`, generated
## by `blender/materials/build_building_materials.py` from the concept sheet
## (`reference-images/architecture/sheets/materials_decay.png`) and hand-paintable
## through the same `painted/` round-trip every other area uses.
##
## A surface is a BASE plus a DECAY, because that is how the sheet draws it: the
## overlays sit on a panel rather than beside it. Ten bases and seven overlays
## give seventy readable surfaces out of seventeen files, and either layer can be
## repainted without touching the other.

const SHADER_PATH := "res://resources/materials/building_surface.gdshader"
const TILE_DIR := "res://resources/materials/building"

## The ten materials the sheet names, in its order.
const BASES := [
	"base_01_riveted_panel",
	"base_02_diamond_plate",
	"base_03_crosshatch_grating",
	"base_04_basement_membrane",
	"base_05_myelin_cabling",
	"base_06_tissue_substrate",
	"base_07_fish_scale_shingle",
	"base_08_vine_rib_tracery",
	"base_09_voronoi_screen",
	"base_10_honeycomb_relief",
]

## The seven decay overlays, in the sheet's order.
const DECAYS := [
	"decay_01_bleed_streaks",
	"decay_02_oxide_dust",
	"decay_03_char_crust",
	"decay_04_membrane_corrosion",
	"decay_05_collapse_cracking",
	"decay_06_candid_mat",
	"decay_07_molten_drip",
]

## What the existing generators already think in. They batch surfaces by ROLE
## ("trim", "mass", "rust", …), so a role maps to a material here and they can
## adopt the library without learning the sheet's vocabulary.
const ROLE_BASE := {
	"mass": "base_01_riveted_panel",
	"trim": "base_02_diamond_plate",
	"service": "base_03_crosshatch_grating",
	"inset": "base_10_honeycomb_relief",
	"rust": "base_01_riveted_panel",
	"membrane": "base_04_basement_membrane",
	"cabling": "base_05_myelin_cabling",
	"tissue": "base_06_tissue_substrate",
	"shingle": "base_07_fish_scale_shingle",
	"tracery": "base_08_vine_rib_tracery",
	"screen": "base_09_voronoi_screen",
}

## Which decay a role tends to wear when nothing says otherwise. A rust batch is
## rust because the level asked for it; a mass wall just weathers.
const ROLE_DECAY := {
	"mass": "decay_02_oxide_dust",
	"trim": "decay_01_bleed_streaks",
	"service": "decay_02_oxide_dust",
	"inset": "decay_05_collapse_cracking",
	"rust": "decay_01_bleed_streaks",
	"membrane": "decay_04_membrane_corrosion",
	"cabling": "decay_04_membrane_corrosion",
	"tissue": "decay_04_membrane_corrosion",
	"shingle": "decay_02_oxide_dust",
	"tracery": "decay_06_candid_mat",
	"screen": "decay_05_collapse_cracking",
}

static var _shader: Shader = null
static var _textures := {}
static var _cache := {}


## The loaded tile for `tile_id`, or null when it is missing. Public because a
## caller checking the library has arrived intact needs to ask for the tiles
## themselves, not just for a material built out of them.
static func tile_texture(tile_id: String) -> Texture2D:
	if _textures.has(tile_id):
		return _textures[tile_id]
	var path := "%s/%s.png" % [TILE_DIR, tile_id]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		var res = load(path)
		tex = res as Texture2D
	_textures[tile_id] = tex
	return tex


static func _shader_resource() -> Shader:
	if _shader == null and ResourceLoader.exists(SHADER_PATH):
		var res = load(SHADER_PATH)
		_shader = res as Shader
	return _shader


## True when the library has its shader and every tile the sheet names.
static func is_available() -> bool:
	if _shader_resource() == null:
		return false
	for id in BASES:
		if tile_texture(str(id)) == null:
			return false
	for id in DECAYS:
		if tile_texture(str(id)) == null:
			return false
	return true


## A surface wearing `base_id` under `decay_id`.
##
## `amount` is how far gone it is; `seed` slides both tiles independently so the
## same pair never lands twice on neighbouring walls — variation without a single
## extra texture. Materials are cached per distinct combination, so a district
## made of a thousand faces still holds a handful of them.
static func surface(
		base_id: String,
		decay_id: String,
		amount: float = 0.6,
		seed: int = 0,
		uv_scale: Vector2 = Vector2.ONE,
		tint: Color = Color.WHITE
	) -> ShaderMaterial:
	var shader := _shader_resource()
	var base_tex := tile_texture(base_id)
	if shader == null or base_tex == null:
		return null
	var decay_tex := tile_texture(decay_id)
	var key := "%s|%s|%.2f|%d|%.2f,%.2f|%s" % [
		base_id, decay_id, amount, seed, uv_scale.x, uv_scale.y, tint.to_html(false)]
	if _cache.has(key):
		return _cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("base_tex", base_tex)
	if decay_tex != null:
		mat.set_shader_parameter("decay_tex", decay_tex)
	mat.set_shader_parameter("uv_scale", uv_scale)
	mat.set_shader_parameter("decay_amount", clampf(amount, 0.0, 1.0))
	mat.set_shader_parameter("tint", tint)
	# The offsets are derived from the seed rather than drawn at random: a wall
	# has to look the same every time the level is generated from the same seed.
	mat.set_shader_parameter("base_offset", _offset(seed, 0))
	mat.set_shader_parameter("decay_offset", _offset(seed, 1))
	_cache[key] = mat
	return mat


static func _offset(seed: int, salt: int) -> Vector2:
	var h := int(abs(seed)) * 73856093 + salt * 19349663
	return Vector2(float(h % 97) / 97.0, float((h / 97) % 89) / 89.0)


## The surface a generator's batch role should wear.
##
## Roles it does not know fall back to the facility's own panel, because an
## unrecognised batch is still a wall and should look like one rather than
## vanish or turn flat-coloured.
static func for_role(role: String, seed: int = 0, amount: float = -1.0) -> ShaderMaterial:
	var base_id := str(ROLE_BASE.get(role, BASES[0]))
	var decay_id := str(ROLE_DECAY.get(role, DECAYS[1]))
	var wear := amount
	if wear < 0.0:
		# Unstated wear varies by seed instead of sitting at one value, so a
		# street reads as weathering unevenly rather than uniformly.
		wear = 0.35 + 0.4 * (float(int(abs(seed)) * 40503 % 101) / 101.0)
	return surface(base_id, decay_id, wear, seed)


## Every combination the sheet allows, as {base, decay} pairs. Seventy of them:
## this is what "variations" means here, and none of them costs a file.
static func all_variations() -> Array:
	var out: Array = []
	for b in BASES:
		for d in DECAYS:
			out.append({"base": str(b), "decay": str(d)})
	return out
