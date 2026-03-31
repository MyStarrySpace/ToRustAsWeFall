shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

// Aster's data-perception overlay. Within clear_radius of character_pos,
// the world renders normally. Beyond it, surfaces are rendered as a
// data schematic: near-black with bright edge lines (depth + color
// Sobel detection) and subtle scanlines.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 character_pos = vec3(0.0);
uniform float clear_radius = 8.0;
uniform float blend_width = 3.0;
uniform vec3 edge_color = vec3(0.29, 0.55, 0.85);
uniform float edge_width = 1.5;
// Blackout zone — region the data perception cannot penetrate (renders as void)
uniform vec3 blackout_pos = vec3(0.0, 0.0, -9999.0);
uniform float blackout_radius = 0.0;
uniform float blackout_blend = 2.0;

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

	// Distance from Aster — drives the blend between normal and data view
	float dist = distance(world_pos, character_pos);
	float data_blend = smoothstep(clear_radius, clear_radius + blend_width, dist);

	if (data_blend > 0.005) {
		vec2 ps = (1.0 / VIEWPORT_SIZE) * edge_width;

		// Depth-based Sobel edge detection
		float dl = texture(depth_tex, SCREEN_UV + vec2(-ps.x, 0.0)).r;
		float dr = texture(depth_tex, SCREEN_UV + vec2(ps.x, 0.0)).r;
		float du = texture(depth_tex, SCREEN_UV + vec2(0.0, -ps.y)).r;
		float dd = texture(depth_tex, SCREEN_UV + vec2(0.0, ps.y)).r;
		float gx = dl - dr;
		float gy = du - dd;
		float depth_edge = smoothstep(0.0002, 0.003, sqrt(gx * gx + gy * gy));

		// Screen-color Laplacian edge detection
		vec3 cl = texture(screen_tex, SCREEN_UV + vec2(-ps.x, 0.0)).rgb;
		vec3 cr = texture(screen_tex, SCREEN_UV + vec2(ps.x, 0.0)).rgb;
		vec3 cu = texture(screen_tex, SCREEN_UV + vec2(0.0, -ps.y)).rgb;
		vec3 cd = texture(screen_tex, SCREEN_UV + vec2(0.0, ps.y)).rgb;
		float lum_c = dot(screen, vec3(0.3, 0.59, 0.11));
		float lum_l = dot(cl, vec3(0.3, 0.59, 0.11));
		float lum_r = dot(cr, vec3(0.3, 0.59, 0.11));
		float lum_u = dot(cu, vec3(0.3, 0.59, 0.11));
		float lum_d = dot(cd, vec3(0.3, 0.59, 0.11));
		float color_edge = smoothstep(0.01, 0.08,
			abs(lum_l + lum_r + lum_u + lum_d - 4.0 * lum_c));

		// Combine edges: depth for geometry, color for material boundaries
		float edge = clamp(max(depth_edge, color_edge * 0.6), 0.0, 1.0);

		// Data view: near-black base with bright edge lines
		vec3 data = vec3(0.01, 0.012, 0.02) + edge * edge_color;

		// Scanline effect
		float scanline = 0.92 + 0.08 * sin(SCREEN_UV.y * VIEWPORT_SIZE.y * 0.3);
		data *= scanline;

		screen = mix(screen, data, data_blend);
	}

	// Blackout zone — data perception reads nothing here
	float bo_dist = distance(world_pos, blackout_pos);
	float bo = 1.0 - smoothstep(blackout_radius - blackout_blend, blackout_radius, bo_dist);
	screen = mix(screen, vec3(0.005, 0.005, 0.01), bo);

	ALBEDO = screen;
	ALPHA = 1.0;
}
