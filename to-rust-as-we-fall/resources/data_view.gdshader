shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

// Aster's visibility overlay. Reconstructs world position from depth buffer
// and additively tints surfaces green based on distance from Aster.
// No occlusion yet — this is a starting point for the full map effect.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 aster_pos = vec3(0.0);
uniform float vis_range = 40.0;
uniform float green_intensity = 0.35;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec3 screen = texture(screen_tex, SCREEN_UV).rgb;

	// Reconstruct world position from depth buffer
	float depth_raw = texture(depth_tex, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view_coords = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_coords.xyz /= view_coords.w;
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(view_coords.xyz, 1.0)).xyz;

	// Distance-based falloff from Aster's position
	float dist = distance(world_pos, aster_pos);
	float falloff = 1.0 - smoothstep(0.0, vis_range, dist);
	falloff *= falloff;

	// Additive green — bypasses dark albedo, always visible
	vec3 green_add = vec3(0.0, green_intensity, green_intensity * 0.3) * falloff;

	ALBEDO = screen + green_add;
	ALPHA = 1.0;
}
