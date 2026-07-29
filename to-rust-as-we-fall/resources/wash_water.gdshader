shader_type spatial;
// THE ONE WASH WATER — every visible water surface in the channels scene
// (deck flood bands, trough bands, the troughs' settled snake) wears this
// shader, so the one-appearance law survives the move to translucency.
//
// Translucent + MOVING: quantized wave fronts sweep DOWNSTREAM in world
// ANGLE space around the drum axis — continuous across every stacked chord
// plate and every band seam (no UV dependency; the painted plates' UV atlas
// is chopped per-plate). Stripe counts are integers per full turn, so the
// atan seam at +/-PI never shows. Posterized glints keep the pixel-art
// grammar — painted steps, not gradients.
//
// depth_draw_always: adjacent chord plates overlap by design (the surface
// never slits); the depth write makes the overlap sliver render ONCE instead
// of double-blending into a darker seam band.
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 water_color : source_color = vec4(0.35, 0.75, 0.85, 1.0);
uniform vec4 emission_color : source_color = vec4(0.3, 0.8, 0.9, 1.0);
uniform float emission_energy = 1.0;
uniform sampler2D albedo_tex : source_color, filter_nearest;
uniform bool has_tex = false;
uniform float water_alpha : hint_range(0.0, 1.0) = 0.5;
uniform float flow_speed = 0.55;    // base drift, turns/sec scaled by stripes
uniform float flow_boost = 1.0;     // wash state: idle 1 / telegraph ~2 / flood ~3
uniform float bob_amp = 0.018;      // cosmetic swell; the kill edge is the Channel's

varying vec3 v_world;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float angn = atan(wp.z, wp.x) / 6.2831853;
	VERTEX.y += sin((angn * 80.0 + TIME * 1.7) * 6.2831853) * bob_amp
		+ sin((angn * 33.0 - TIME * 1.1) * 6.2831853) * bob_amp * 0.6;
	v_world = wp;
}

void fragment() {
	float angn = atan(v_world.z, v_world.x) / 6.2831853;
	float r = length(v_world.xz);
	float t = TIME * flow_speed * flow_boost;
	// three stripe sets at co-prime frequencies; fronts drift toward
	// DECREASING angle — the same direction the sweep carries a body
	float w1 = fract(angn * 96.0 + t);
	float w2 = fract(angn * 168.0 + r * 1.9 + t * 1.45);
	float w3 = fract(angn * 56.0 - r * 1.1 + t * 0.62);
	float glint = step(0.82, w1) * 0.5 + step(0.86, w2) * 0.35 + step(0.8, w3) * 0.3;
	glint = floor(min(glint, 0.85) * 3.0 + 0.5) / 3.0;
	vec3 base = has_tex ? texture(albedo_tex, UV).rgb : vec3(1.0);
	ALBEDO = base * water_color.rgb;
	float fr = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
	ALPHA = clamp(water_alpha + glint * 0.22 + fr * 0.18, 0.0, 0.92);
	EMISSION = emission_color.rgb * emission_energy * (0.55 + glint * 0.9 + fr * 0.35);
	ROUGHNESS = 0.18;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
