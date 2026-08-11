shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// A BUILDING SURFACE IS A MATERIAL PLUS WHAT HAS HAPPENED TO IT.
//
// The concept sheet (reference-images/architecture/sheets/materials_decay.png)
// draws its decay overlays ON a base panel rather than beside it, so the two are
// authored as separate tiles and combined here. Ten bases and seven overlays make
// seventy surfaces out of seventeen files, and either layer can be repainted on
// its own -- baking the combinations would mean fixing the rust ten times.
//
// Both layers stay hand-paintable: they are ordinary PNGs under
// resources/materials/building/, and the build that generates them lets a file
// dropped in blender/materials/painted/ win.

uniform sampler2D base_tex : source_color, filter_nearest, repeat_enable;
uniform sampler2D decay_tex : source_color, filter_nearest, repeat_enable;

uniform vec2 uv_scale = vec2(1.0, 1.0);
// Per-instance variation with no extra texture: the same pair of tiles lands
// somewhere different on every wall, so a row of them stops reading as stamped.
uniform vec2 base_offset = vec2(0.0, 0.0);
uniform vec2 decay_offset = vec2(0.0, 0.0);
uniform float decay_amount : hint_range(0.0, 1.0) = 0.6;
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float roughness_base : hint_range(0.0, 1.0) = 0.85;
// Decay is matte: rust and fungus do not shine the way the panel under them does.
uniform float roughness_decay : hint_range(0.0, 1.0) = 0.98;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec2 uv = UV * uv_scale;
	vec4 base = texture(base_tex, uv + base_offset);
	vec4 decay = texture(decay_tex, uv + decay_offset);

	// The overlay's alpha is COVERAGE -- how much of this has happened here --
	// scaled by how far gone this particular surface is.
	float cover = decay.a * decay_amount;
	vec3 albedo = mix(base.rgb, decay.rgb, cover) * tint;

	ALBEDO = albedo;
	ROUGHNESS = mix(roughness_base, roughness_decay, cover);
	METALLIC = 0.0;

	// An OPEN material -- a grating, a mesh screen -- carries real holes in its
	// base tile, and decay must never plate them over: rust on a grate runs on
	// the bars, and where there is no bar there is nothing to run on.
	ALPHA = base.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
}
