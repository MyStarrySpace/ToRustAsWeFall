shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

// Aster's data-perception overlay. Within clear_radius of character_pos,
// the world renders normally. Beyond it, rendered geometry receives a stable
// blue register tint; explicit world guides carry the actual schematic data.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 character_pos = vec3(0.0);
uniform float clear_radius = 8.0;
uniform float blend_width = 3.0;
uniform vec3 data_tint = vec3(0.45, 0.62, 0.78);
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
	// Godot's Web compatibility target can expose either conventional or
	// reversed-Z clears depending on the browser/backend path. Treat BOTH exact
	// depth extremes as untouched background; rendered geometry lies between
	// them. This avoids compiling the wrong background convention into WebGL.
	return step(0.000001, depth_raw) * (1.0 - step(0.999999, depth_raw));
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
	float data_blend = smoothstep(clear_radius, clear_radius + blend_width, dist)
		* geometry_at_depth(depth_raw);

	if (data_blend > 0.005) {
		// The useful schematic information is authored in world-space guides. A
		// depth-edge pass duplicated that information and turned repeated deck
		// slats into full-screen bands in Web. A single-sample geometry tint is
		// stable, cheap, and cannot invent edges at camera cuts or texture detail.
		vec3 data = screen * data_tint + vec3(0.01, 0.018, 0.03);
		screen = mix(screen, data, data_blend * 0.72);
	}

	// Blackout zone — data perception reads nothing here
	float bo_dist = distance(world_pos, blackout_pos);
	float bo = 1.0 - smoothstep(blackout_radius - blackout_blend, blackout_radius, bo_dist);
	screen = mix(screen, vec3(0.005, 0.005, 0.01), bo);

	ALBEDO = screen;
	ALPHA = 1.0;
}
