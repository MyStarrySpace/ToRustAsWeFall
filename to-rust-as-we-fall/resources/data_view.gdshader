shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

// Aster's data-perception overlay. Within clear_radius of character_pos,
// the world renders normally. Beyond it, surfaces are rendered as a
// data schematic: near-black with depth-derived geometry lines.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 character_pos = vec3(0.0);
uniform float clear_radius = 8.0;
uniform float blend_width = 3.0;
uniform vec3 edge_color = vec3(0.55, 0.80, 1.0);
uniform float edge_width = 1.5;
// Blackout zone — region the data perception cannot penetrate (renders as void)
uniform vec3 blackout_pos = vec3(0.0, 0.0, -9999.0);
uniform float blackout_radius = 0.0;
uniform float blackout_blend = 2.0;

float depth_to_ndc(float depth_raw) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return depth_raw * 2.0 - 1.0;
#else
	return depth_raw;
#endif
}

float geometry_at_depth(float depth_raw) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// Compatibility uses conventional depth: the untouched background is 1.
	return 1.0 - step(0.999999, depth_raw);
#else
	// Forward+/Mobile use reversed Z: the untouched background is 0.
	return step(0.000001, depth_raw);
#endif
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec3 screen = texture(screen_tex, SCREEN_UV).rgb;

	// Reconstruct world position from depth buffer
	float depth_raw = texture(depth_tex, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_to_ndc(depth_raw));
	vec4 view_coords = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_coords.xyz /= view_coords.w;
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(view_coords.xyz, 1.0)).xyz;

	// Distance from Aster — drives the blend between normal and data view
	float dist = distance(world_pos, character_pos);
	float data_blend = smoothstep(clear_radius, clear_radius + blend_width, dist);

	if (data_blend > 0.005) {
		vec2 ps = (1.0 / VIEWPORT_SIZE) * edge_width;

		// Use depth curvature, not a first derivative. A Sobel gradient paints
		// every steep/slanted surface as an "edge"; on the lower deck that turned
		// a nearby wall into a dense stippled wedge. The centered second derivative
		// stays near zero across a continuous plane and responds at silhouettes and
		// actual depth breaks.
		float dl = texture(depth_tex, SCREEN_UV + vec2(-ps.x, 0.0)).r;
		float dr = texture(depth_tex, SCREEN_UV + vec2(ps.x, 0.0)).r;
		float du = texture(depth_tex, SCREEN_UV + vec2(0.0, -ps.y)).r;
		float dd = texture(depth_tex, SCREEN_UV + vec2(0.0, ps.y)).r;
		float depth_curvature = abs(dl + dr - 2.0 * depth_raw)
			+ abs(du + dd - 2.0 * depth_raw);
		float depth_edge = smoothstep(0.00005, 0.0015, depth_curvature);

		// Geometry edges only. A screen-color Laplacian used to reinterpret every
		// floor grate, dither texel, and iron-field material detail as geometry,
		// producing dense white pixels and a large GPU cost in the lower route.
		// Never ink the empty side of a silhouette. Camera-occlusion holes put
		// geometry beside background pixels; treating those background pixels as
		// drawable edges produced the giant white/cyan elevator boundary and the
		// old dither produced a cloud of individual bright pixels.
		float edge = depth_edge * geometry_at_depth(depth_raw);

		// Data view: near-black base with bright edge lines
		vec3 data = vec3(0.01, 0.012, 0.02) + edge * edge_color;

		screen = mix(screen, data, data_blend);
	}

	// Blackout zone — data perception reads nothing here
	float bo_dist = distance(world_pos, blackout_pos);
	float bo = 1.0 - smoothstep(blackout_radius - blackout_blend, blackout_radius, bo_dist);
	screen = mix(screen, vec3(0.005, 0.005, 0.01), bo);

	ALBEDO = screen;
	ALPHA = 1.0;
}
