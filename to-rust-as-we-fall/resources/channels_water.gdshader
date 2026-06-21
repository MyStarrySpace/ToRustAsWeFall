shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, diffuse_burley;

// Animated FLOOD-WATER surface for the channels (flooded Sector 12). The brightness comes from the BASE
// colours + a strong self-EMISSION (so it reads as glowing teal water in the dark drainage) — the dark
// pixel-art tile is used only for RIPPLE detail, never to darken the colour toward black (the earlier bug:
// dark tile x dark tint x luminance-scaled emission summed to near-invisible). Two world-space scroll
// layers + a sine warp animate the surface on engine TIME; a fresnel + crest band lays foam. Purely
// COSMETIC (@rendering_only): animates on shader TIME, never gates game state. GDShader forbids `return`
// in fragment()/vertex().

uniform sampler2D water_tex : source_color, filter_nearest, repeat_enable, hint_default_white;
uniform vec3 shallow_color : source_color = vec3(0.22, 0.74, 0.88);  // lit teal crest water
uniform vec3 deep_color : source_color = vec3(0.06, 0.34, 0.48);     // iron-teal trough (still readable)
uniform vec3 foam_color : source_color = vec3(0.78, 0.98, 1.0);      // crest / edge foam
uniform float flow_speed = 0.15;       // UV scroll along the flow dir, per second
uniform float flow_dir_x = 1.0;
uniform float flow_dir_y = 0.2;
uniform float tex_scale = 0.5;         // world-space tile repeat (smaller = bigger tiles)
uniform float warp_amount = 0.05;      // sine UV warp depth (the living wobble)
uniform float warp_speed = 0.9;
uniform float ripple_gain : hint_range(0.5, 4.0) = 2.2;     // remaps the dark tile into a usable 0..1 ripple
uniform float foam_strength : hint_range(0.0, 2.0) = 0.8;
uniform float water_alpha : hint_range(0.0, 1.0) = 0.88;    // translucency (see the deck faintly through it)
uniform float emission_strength : hint_range(0.0, 4.0) = 2.2;  // self-glow — what makes the flood READ

varying vec3 v_world;
varying vec3 v_normal;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float t = TIME;
	vec2 fdir = normalize(vec2(flow_dir_x, flow_dir_y) + vec2(0.0001));
	// World-XZ projected UVs so the tile repeats in WORLD space (lines up across the segmented flood boxes).
	vec2 base_uv = v_world.xz * tex_scale;
	vec2 warp = vec2(sin(base_uv.y * 3.0 + t * warp_speed), cos(base_uv.x * 3.0 + t * warp_speed * 1.2)) * warp_amount;
	vec2 uv_a = base_uv + warp + fdir * (t * flow_speed);
	vec2 uv_b = base_uv * 1.6 - warp * 0.6 + fdir.yx * (-t * flow_speed * 0.7);
	// Ripple field from the tile luminance, gained UP into a usable 0..1 (the tile is intentionally dark).
	float ra = dot(texture(water_tex, uv_a).rgb, vec3(0.299, 0.587, 0.114));
	float rb = dot(texture(water_tex, uv_b).rgb, vec3(0.299, 0.587, 0.114));
	float ripple = clamp(mix(ra, rb, 0.45) * ripple_gain, 0.0, 1.0);

	// Base colour interpolates BRIGHT shallow over deep by the ripple — never multiplied toward black.
	vec3 col = mix(deep_color, shallow_color, ripple);

	// Foam: fresnel rim at grazing angles + the bright crests.
	float fres = pow(clamp(1.0 - abs(dot(normalize(v_normal), normalize(VIEW))), 0.0, 1.0), 3.0);
	float crest = smoothstep(0.6, 0.9, ripple);
	float foam = clamp(fres * 0.5 + crest * 0.8, 0.0, 1.0) * foam_strength;
	col = mix(col, foam_color, clamp(foam, 0.0, 1.0));

	ALBEDO = col;
	ROUGHNESS = 0.18;
	METALLIC = 0.0;
	EMISSION = col * emission_strength;   // bright, flat self-glow so the flood is unmistakable in the dark
	ALPHA = clamp(water_alpha + foam * 0.1, 0.0, 1.0);
}
