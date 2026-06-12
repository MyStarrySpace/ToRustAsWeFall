shader_type spatial;
// An expanded inverted hull that reads as energy emitting from the object's outline. The crisp
// white outline stays a separate (narrower) shell; this one reaches further out, masks to the
// silhouette with a fresnel term, and fills that band with time-morphing noise — so instead of
// discrete particles it looks like the outline is shedding shimmering energy. Additive, no depth
// write, drawn after the mesh.
render_mode unshaded, cull_front, depth_draw_never, blend_add, shadows_disabled, fog_disabled;

uniform vec4 glow_color : source_color = vec4(1.0, 0.55, 0.2, 1.0);
uniform float expand = 0.34;        // how far the glow reaches past the surface (the mask band)
uniform float glow_strength = 2.2;
uniform float edge_power = 1.4;     // how tightly the glow hugs the silhouette (low = wider, softer band)
uniform float noise_scale = 1.0;    // world-space noise frequency (low = large grains)
uniform float scroll_speed = 0.13;  // how fast the noise morphs
uniform float intensity = 1.0;      // overall on/off + fade
uniform sampler2D noise_tex : repeat_enable, filter_linear;

varying vec3 v_world;

// Same depth trick as the crisp hull: bias the glow band behind the mesh so thin geometry shows a
// rim of energy instead of an additive wash over its whole face.
uniform float depth_bias = 0.004;

void vertex() {
	VERTEX += NORMAL * expand;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	POSITION.z -= depth_bias * POSITION.w;
}

// Two scrolling samples of the noise multiplied → a churning, morphing field rather than a flat
// scroll, so it reads as living energy. World-space + two axis projections avoids UV seams.
float morph_noise(vec3 p) {
	vec2 a = p.xy * noise_scale + vec2(TIME * scroll_speed, TIME * scroll_speed * 0.6);
	vec2 b = p.zy * noise_scale - vec2(TIME * scroll_speed * 0.5, TIME * scroll_speed * 0.9);
	return texture(noise_tex, a).r * texture(noise_tex, b).r;
}

void fragment() {
	// Silhouette mask: strongest where the (back-face) normal grazes the view — the outline edge
	// — fading inward. This is the "expanded outline used as a mask".
	float ndotv = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = pow(1.0 - ndotv, edge_power);
	float n = morph_noise(v_world);
	// The visible band IS already the silhouette (depth-occluded within the mesh), so keep a base
	// glow across the whole band + an edge emphasis — the noise then breaks it into living energy.
	// Softer overall: a lower base keeps the inner band airy, and the squared edge term makes the
	// reach FADE OUT toward the rim instead of cutting off at the hull boundary.
	float mask = clamp((0.3 + 0.7 * edge * edge) * n * 1.7, 0.0, 1.0) * intensity;
	ALBEDO = glow_color.rgb;
	EMISSION = glow_color.rgb * glow_strength;
	ALPHA = mask * glow_color.a;
}
