shader_type spatial;
render_mode cull_disabled;

// Crossfades two existing district atlas tiles. Vertex color R carries the
// generator-authored progress through the threshold, so the blend follows a
// curved corridor/helix instead of assuming one global axis.
uniform sampler2D from_texture : source_color, filter_nearest, repeat_enable;
uniform sampler2D to_texture : source_color, filter_nearest, repeat_enable;
uniform vec4 threshold_tint : source_color = vec4(0.45, 0.55, 0.58, 1.0);

varying vec3 world_position;
varying vec3 world_normal;
varying float transition_progress;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	transition_progress = clamp(COLOR.r, 0.0, 1.0);
}

vec3 triplanar_sample(sampler2D atlas, vec3 p, vec3 n) {
	vec3 weights = pow(abs(n), vec3(6.0));
	weights /= max(weights.x + weights.y + weights.z, 0.0001);
	vec3 x_sample = texture(atlas, p.zy).rgb;
	vec3 y_sample = texture(atlas, p.xz).rgb;
	vec3 z_sample = texture(atlas, p.xy).rgb;
	return x_sample * weights.x + y_sample * weights.y + z_sample * weights.z;
}

void fragment() {
	vec3 from_color = triplanar_sample(from_texture, world_position, world_normal);
	vec3 to_color = triplanar_sample(to_texture, world_position, world_normal);
	float eased = smoothstep(0.0, 1.0, transition_progress);
	vec3 surface_color = mix(from_color, to_color, eased);
	// A restrained middle wash makes the threshold readable without becoming a
	// glowing checkpoint stripe or competing with causal overlays.
	float threshold = 1.0 - abs(eased * 2.0 - 1.0);
	surface_color = mix(surface_color, surface_color * threshold_tint.rgb, threshold * 0.08);
	ALBEDO = surface_color;
	ROUGHNESS = 0.9;
}
