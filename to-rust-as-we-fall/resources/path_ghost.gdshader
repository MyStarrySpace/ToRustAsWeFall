shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;

// Behind-geometry fallback for movement ribbons. This pass ignores the depth
// test so a route remains legible through an occluder, but samples opaque scene
// depth and discards itself wherever the solid ground ribbon is visible.
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 tint : source_color = vec4(0.5, 0.75, 1.0, 1.0);
uniform float occlusion_bias = 0.035;
uniform float checker_scale = 7.0;

varying vec3 path_world_pos;

float depth_to_ndc(float depth_raw) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return depth_raw * 2.0 - 1.0;
#else
	return depth_raw;
#endif
}

float geometry_at_depth(float depth_raw) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return 1.0 - step(0.999999, depth_raw);
#else
	return step(0.000001, depth_raw);
#endif
}

void vertex() {
	path_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float scene_depth_raw = texture(depth_tex, SCREEN_UV).r;
	if (geometry_at_depth(scene_depth_raw) < 0.5) {
		discard;
	}

	vec3 scene_ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_to_ndc(scene_depth_raw));
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(scene_ndc, 1.0);
	scene_view.xyz /= scene_view.w;
	float scene_distance = -scene_view.z;
	float path_distance = -VERTEX.z;
	// Coplanar floor depth and precision noise stay solid. Only a meaningful
	// opaque obstruction produces the world-anchored checker fallback.
	if (scene_distance + occlusion_bias >= path_distance) {
		discard;
	}

	vec2 checker_cell = floor(path_world_pos.xz * checker_scale);
	if (mod(checker_cell.x + checker_cell.y, 2.0) >= 1.0) {
		discard;
	}
	ALBEDO = tint.rgb;
	ALPHA = 1.0;
}
