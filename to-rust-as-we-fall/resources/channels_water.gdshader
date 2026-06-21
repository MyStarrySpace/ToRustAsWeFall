shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Animated FLOOD-WATER surface for the channels (flooded Sector 12). Samples a tileable pixel-art
// water tile (channels_water_v*.png) with NEAREST + REPEAT (crisp pixel grammar) and ANIMATES it:
// the tile scrolls along the flow direction over engine TIME, with a second counter-scrolled layer
// plus a sine WARP so the surface lives (not a flat slab sliding). A depth tint darkens the troughs,
// a foam/fresnel band brightens the edges, and an iron/teal tint keeps the Sector-12 mood. Purely
// COSMETIC: it animates on the wall-clock/shader TIME (@rendering_only) — NEVER gates game state.
//
// GDShader forbids `return` in fragment()/vertex(); branches are nested ifs (discard is allowed but
// unused here). Tuning knobs (flow_speed/tint/foam/alpha/...) are uniforms for the user to eyeball.

uniform sampler2D water_tex : source_color, filter_nearest, repeat_enable, hint_default_white;
uniform vec3 deep_tint : source_color = vec3(0.04, 0.16, 0.22);   // iron-teal depth (multiplies the trough)
uniform vec3 surface_tint : source_color = vec3(0.55, 0.95, 1.0); // teal cast over the lit water
uniform vec3 foam_color : source_color = vec3(0.70, 0.95, 1.0);   // crest/edge foam
uniform float flow_speed = 0.12;       // tile scrolls this many UV/sec along the flow dir
uniform float flow_dir_x = 1.0;        // flow direction in tile-UV space (normalized internally)
uniform float flow_dir_y = 0.15;
uniform float tex_scale = 0.55;        // tile repeats: smaller = bigger tiles
uniform float warp_amount = 0.06;      // sine UV warp depth (the living wobble)
uniform float warp_speed = 0.8;        // warp animation rate
uniform float foam_strength : hint_range(0.0, 2.0) = 0.7;   // edge/fresnel foam intensity
uniform float depth_strength : hint_range(0.0, 1.0) = 0.55; // how dark the troughs sink
uniform float water_alpha : hint_range(0.0, 1.0) = 0.82;    // overall translucency
uniform float emission_strength : hint_range(0.0, 3.0) = 1.1; // self-glow (dark drainage reads)

varying vec3 v_world;
varying vec3 v_normal;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float t = TIME;
	vec2 fdir = normalize(vec2(flow_dir_x, flow_dir_y) + vec2(0.0001));
	// World-XZ projected UVs so the tile repeats in WORLD space (no per-mesh UV setup, like the
	// triplanar tiles) and lines up across the segmented flood boxes.
	vec2 base_uv = v_world.xz * tex_scale;

	// A sine WARP that breathes the surface — two crossed waves on TIME so ripples drift, not slide.
	vec2 warp = vec2(
		sin(base_uv.y * 3.0 + t * warp_speed),
		cos(base_uv.x * 3.0 + t * warp_speed * 1.3)
	) * warp_amount;

	// Two layers scrolling at different speeds/directions so the flow looks turbulent, not a flat pan.
	vec2 uv_a = base_uv + warp + fdir * (t * flow_speed);
	vec2 uv_b = base_uv * 1.7 - warp * 0.6 + fdir.yx * (-t * flow_speed * 0.6);
	vec3 layer_a = texture(water_tex, uv_a).rgb;
	vec3 layer_b = texture(water_tex, uv_b).rgb;
	vec3 water = mix(layer_a, layer_b, 0.45);

	// Luminance of the sampled water -> how "lit" this pixel is (crests are bright, troughs dark).
	float lum = dot(water, vec3(0.299, 0.587, 0.114));

	// Depth tint: sink the troughs toward the dark iron-teal deep colour, keep the crests teal-lit.
	vec3 col = mix(deep_tint, water * surface_tint, mix(1.0 - depth_strength, 1.0, lum));

	// Fresnel foam at grazing angles + on the bright crests (a tile-based foam band): brighten edges.
	float fres = pow(clamp(1.0 - abs(dot(normalize(v_normal), normalize(VIEW))), 0.0, 1.0), 2.0);
	float crest = smoothstep(0.55, 0.85, lum);
	float foam = clamp(fres * 0.6 + crest * 0.7, 0.0, 1.0) * foam_strength;
	col = mix(col, foam_color, clamp(foam, 0.0, 1.0));

	ALBEDO = col;
	ROUGHNESS = 0.25;
	METALLIC = 0.0;
	// Self-emission so the flood reads in the dark drainage (the surge you got washed by is visible).
	EMISSION = col * emission_strength * (0.35 + 0.65 * lum);
	ALPHA = clamp(water_alpha + foam * 0.15, 0.0, 1.0);
}
