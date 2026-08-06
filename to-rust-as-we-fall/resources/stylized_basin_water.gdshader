shader_type spatial;

// One continuous basin surface inspired by Alexander Ameye's stylized-water
// breakdown: depth colour, refracted scene colour, distorted surface foam,
// depth intersection foam, Fresnel/horizon colour, animated normals, and waves.
// Gameplay never reads this shader; BasinWater remains the sole water authority.
render_mode blend_mix, cull_disabled, depth_draw_never, diffuse_burley, specular_schlick_ggx;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

uniform vec4 shallow_color : source_color = vec4(0.16, 0.62, 0.72, 0.72);
uniform vec4 deep_color : source_color = vec4(0.025, 0.15, 0.23, 0.92);
uniform vec3 horizon_color : source_color = vec3(0.42, 0.88, 0.92);
uniform vec3 foam_color : source_color = vec3(0.82, 0.98, 1.0);
uniform float depth_distance : hint_range(0.1, 8.0) = 3.2;
uniform float horizon_power : hint_range(0.5, 8.0) = 3.5;
uniform float refraction_strength : hint_range(0.0, 0.05) = 0.012;
uniform float intersection_width : hint_range(0.02, 2.0) = 0.42;
uniform float surface_foam_cutoff : hint_range(0.0, 1.0) = 0.76;
uniform float foam_scale : hint_range(0.05, 4.0) = 0.62;
uniform float flow_speed : hint_range(0.0, 3.0) = 0.32;
uniform vec2 flow_direction = vec2(0.92, 0.38);
uniform float wave_height : hint_range(0.0, 0.25) = 0.055;
uniform float wave_scale : hint_range(0.1, 5.0) = 1.15;
uniform float emission_strength : hint_range(0.0, 4.0) = 0.72;
uniform float alert_strength : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_position;

float wave_field(vec2 p, float t) {
	vec2 d1 = normalize(vec2(0.91, 0.42));
	vec2 d2 = normalize(vec2(-0.34, 0.94));
	vec2 d3 = normalize(vec2(0.63, -0.78));
	return sin(dot(p, d1) * 1.7 + t * 1.05) * 0.48
		+ sin(dot(p, d2) * 2.6 - t * 0.72) * 0.31
		+ sin(dot(p, d3) * 4.1 + t * 0.43) * 0.21;
}

float water_noise(vec2 p) {
	float a = sin(p.x + sin(p.y * 1.37));
	float b = sin(p.y * 1.71 - cos(p.x * 1.13));
	float c = sin((p.x + p.y) * 0.73);
	return (a + b + c) / 6.0 + 0.5;
}

vec3 scene_view_position(vec2 uv, mat4 inverse_projection) {
	float raw_depth = texture(depth_texture, uv).r;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, raw_depth) * 2.0 - 1.0;
	#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw_depth);
	#endif
	vec4 view = inverse_projection * vec4(ndc, 1.0);
	return view.xyz / max(abs(view.w), 0.00001);
}

void vertex() {
	vec3 original_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += wave_field(original_world.xz * wave_scale, TIME) * wave_height;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 direction = normalize(flow_direction + vec2(0.0001));
	vec2 world_uv = world_position.xz * foam_scale;
	float t = TIME * flow_speed;
	float broad = water_noise(world_uv + direction * t);
	float detail = water_noise(world_uv * 1.83 - direction.yx * t * 1.37);
	float ripples = mix(broad, detail, 0.42);

	// Reconstruct opaque scene depth. VERTEX is view-space here, so the
	// difference is stable for both perspective and the basin's orthographic view.
	vec3 scene_view = scene_view_position(SCREEN_UV, INV_PROJECTION_MATRIX);
	float water_depth = max(0.0, -scene_view.z - (-VERTEX.z));
	float depth_mix = smoothstep(0.0, depth_distance, water_depth);

	vec2 refract_offset = vec2(
		water_noise(world_uv * 1.31 + vec2(t, -t * 0.7)) - 0.5,
		water_noise(world_uv.yx * 1.57 + vec2(-t * 0.6, t)) - 0.5
	) * refraction_strength;
	vec2 refracted_uv = clamp(SCREEN_UV + refract_offset, vec2(0.001), vec2(0.999));
	// Reject refraction that samples geometry in front of the surface.
	vec3 refracted_scene_view = scene_view_position(refracted_uv, INV_PROJECTION_MATRIX);
	if (-refracted_scene_view.z <= -VERTEX.z + 0.01) {
		refracted_uv = SCREEN_UV;
	}
	vec3 scene_color = textureLod(screen_texture, refracted_uv, 0.0).rgb;

	float dx = wave_field((world_position.xz + vec2(0.045, 0.0)) * wave_scale, TIME)
		- wave_field((world_position.xz - vec2(0.045, 0.0)) * wave_scale, TIME);
	float dz = wave_field((world_position.xz + vec2(0.0, 0.045)) * wave_scale, TIME)
		- wave_field((world_position.xz - vec2(0.0, 0.045)) * wave_scale, TIME);
	vec3 animated_normal = normalize(vec3(-dx * wave_height * 11.0, 1.0, -dz * wave_height * 11.0));
	NORMAL_MAP = animated_normal.xzy * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.8;

	float fresnel = pow(clamp(1.0 - dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), horizon_power);
	vec3 tint = mix(shallow_color.rgb, deep_color.rgb, depth_mix);
	float tint_alpha = mix(shallow_color.a, deep_color.a, depth_mix);
	vec3 color = mix(scene_color, tint, tint_alpha);
	color = mix(color, horizon_color, fresnel * 0.58);

	float surface_foam = smoothstep(surface_foam_cutoff, min(1.0, surface_foam_cutoff + 0.12), ripples);
	float intersection = 1.0 - smoothstep(0.0, intersection_width, water_depth);
	float broken_edge = smoothstep(0.36, 0.7, water_noise(world_uv * 2.15 - direction * t * 1.8));
	float foam = clamp(surface_foam * 0.38 + intersection * broken_edge, 0.0, 1.0);
	foam = max(foam, alert_strength * smoothstep(0.42, 0.68, ripples) * 0.72);
	color = mix(color, foam_color, foam);

	ALBEDO = color;
	EMISSION = color * emission_strength + foam_color * foam * (0.3 + alert_strength * 0.9);
	ROUGHNESS = mix(0.22, 0.08, foam);
	SPECULAR = 0.72;
	METALLIC = 0.0;
	ALPHA = clamp(mix(shallow_color.a, deep_color.a, depth_mix) + foam * 0.12, 0.0, 0.96);
}
