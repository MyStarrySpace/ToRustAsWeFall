shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

// Full-screen post-process for Aster's sim. Depth edges catch object
// silhouettes, while a gentler color edge keeps same-depth details legible.
// Edge ink uses the minimum nearby material color multiplied by the
// scene-average screen color, yielding a darker outline that stays tied to
// the room palette without averaging in transparent/background pixels.
// Very bright emissive UI regions suppress color-edge outlines so glowing
// texture pixels do not get mistaken for object silhouettes.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 outline_color = vec3(0.0, 0.0, 0.0);
uniform float texture_outline_mix = 1.0;
uniform float texture_outline_darkness = 0.82;
uniform float texture_outline_saturation = 2.0;
uniform float texture_outline_floor = 0.02;
uniform float scene_average_lod = 8.0;
uniform float scene_average_influence = 1.0;
uniform float scene_average_saturation = 1.6;
uniform float local_min_mix = 0.9;
uniform float outline_width = 1.0;
uniform float close_outline_width = 4.0;
uniform float far_outline_width = 1.25;
uniform float close_distance = 2.0;
uniform float far_distance = 14.0;
uniform float outline_strength = 1.0;
uniform float depth_edge_low = 0.00018;
uniform float depth_edge_high = 0.0025;
uniform float color_edge_low = 0.035;
uniform float color_edge_high = 0.14;
uniform float color_edge_weight = 0.35;
uniform float bright_region_threshold = 0.72;
uniform float bright_region_feather = 0.18;
uniform float bright_color_edge_suppression = 1.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float luminance(vec3 color) {
	return dot(color, vec3(0.3, 0.59, 0.11));
}

vec3 saturate_color(vec3 color, float amount) {
	return mix(vec3(luminance(color)), color, amount);
}

vec3 darker_color(vec3 current, vec3 candidate) {
	if (luminance(candidate) < luminance(current)) {
		return candidate;
	}
	return current;
}

vec3 component_min_color(vec3 center, vec3 left, vec3 right, vec3 up, vec3 down) {
	return min(min(min(min(center, left), right), up), down);
}

vec3 scene_average_color() {
	// Mipmapped screen texture sampling approximates the current viewport's
	// average color without a separate reduction pass.
	return saturate_color(textureLod(screen_tex, vec2(0.5, 0.5), scene_average_lod).rgb,
		scene_average_saturation);
}

vec3 darker_nearby_color(vec3 center, vec3 left, vec3 right, vec3 up, vec3 down) {
	vec3 local_color = center;
	local_color = darker_color(local_color, left);
	local_color = darker_color(local_color, right);
	local_color = darker_color(local_color, up);
	local_color = darker_color(local_color, down);
	return local_color;
}

vec3 local_outline_color(vec3 center, vec3 left, vec3 right, vec3 up, vec3 down, vec3 scene_average) {
	vec3 darkest_color = darker_nearby_color(center, left, right, up, down);
	vec3 minimum_color = component_min_color(center, left, right, up, down);
	vec3 local_color = mix(darkest_color, minimum_color, local_min_mix);
	vec3 multiplied_color = local_color * mix(vec3(1.0), scene_average, scene_average_influence);
	vec3 textured_ink = saturate_color(multiplied_color, texture_outline_saturation);
	textured_ink *= texture_outline_darkness;
	vec3 colored_floor = saturate_color(scene_average, texture_outline_saturation) * texture_outline_floor;
	textured_ink = max(textured_ink, colored_floor);
	return mix(outline_color, textured_ink, texture_outline_mix);
}

void fragment() {
	vec3 screen = texture(screen_tex, SCREEN_UV).rgb;
	float depth_raw = texture(depth_tex, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view_coords = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_coords.xyz /= view_coords.w;
	float camera_distance = max(0.0, -view_coords.z);
	float distance_blend = smoothstep(close_distance, far_distance, camera_distance);
	float scaled_width = mix(close_outline_width, far_outline_width, distance_blend) * outline_width;
	vec2 ps = (1.0 / VIEWPORT_SIZE) * scaled_width;

	float depth_l = texture(depth_tex, SCREEN_UV + vec2(-ps.x, 0.0)).r;
	float depth_r = texture(depth_tex, SCREEN_UV + vec2(ps.x, 0.0)).r;
	float depth_u = texture(depth_tex, SCREEN_UV + vec2(0.0, -ps.y)).r;
	float depth_d = texture(depth_tex, SCREEN_UV + vec2(0.0, ps.y)).r;
	float depth_gx = depth_l - depth_r;
	float depth_gy = depth_u - depth_d;
	float depth_edge = smoothstep(
		depth_edge_low,
		depth_edge_high,
		sqrt(depth_gx * depth_gx + depth_gy * depth_gy)
	);

	vec3 color_l = texture(screen_tex, SCREEN_UV + vec2(-ps.x, 0.0)).rgb;
	vec3 color_r = texture(screen_tex, SCREEN_UV + vec2(ps.x, 0.0)).rgb;
	vec3 color_u = texture(screen_tex, SCREEN_UV + vec2(0.0, -ps.y)).rgb;
	vec3 color_d = texture(screen_tex, SCREEN_UV + vec2(0.0, ps.y)).rgb;
	float lum_c = luminance(screen);
	float lum_l = luminance(color_l);
	float lum_r = luminance(color_r);
	float lum_u = luminance(color_u);
	float lum_d = luminance(color_d);
	float brightest_luma = max(max(max(max(lum_c, lum_l), lum_r), lum_u), lum_d);
	float bright_region = smoothstep(
		bright_region_threshold,
		bright_region_threshold + bright_region_feather,
		brightest_luma
	);
	float color_edge_suppression = mix(1.0, 1.0 - bright_color_edge_suppression, bright_region);
	float color_edge = smoothstep(
		color_edge_low,
		color_edge_high,
		abs(lum_l + lum_r + lum_u + lum_d - 4.0 * lum_c)
	) * color_edge_weight * color_edge_suppression;

	float edge = clamp(max(depth_edge, color_edge), 0.0, 1.0) * outline_strength;
	vec3 average_color = scene_average_color();
	vec3 edge_color = local_outline_color(screen, color_l, color_r, color_u, color_d, average_color);
	ALBEDO = mix(screen, edge_color, edge);
	ALPHA = 1.0;
}
