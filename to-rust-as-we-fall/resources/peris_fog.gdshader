shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

// Peris's memory-fog perception. Within clear_radius, the world renders
// normally. Beyond it, the scene fades into warm desaturated fog —
// shapes are visible but indistinct, like a half-remembered room.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 character_pos = vec3(0.0);
uniform float clear_radius = 8.0;
uniform float blend_width = 4.0;
uniform vec3 fog_color = vec3(0.15, 0.1, 0.07);
uniform float desaturation = 0.8;

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

	// Distance from character — drives the fog blend
	float dist = distance(world_pos, character_pos);
	float fog_blend = smoothstep(clear_radius, clear_radius + blend_width, dist);

	if (fog_blend > 0.005) {
		// Desaturate: convert to luminance and mix back
		float lum = dot(screen, vec3(0.3, 0.59, 0.11));
		vec3 desat = mix(screen, vec3(lum), desaturation * fog_blend);

		// Warm tint: blend toward fog color
		vec3 fogged = mix(desat, fog_color, fog_blend * 0.7);

		// Reduce contrast in the fog zone
		fogged = mix(fogged, vec3(dot(fogged, vec3(0.3, 0.59, 0.11))), fog_blend * 0.3);

		screen = fogged;
	}

	ALBEDO = screen;
	ALPHA = 1.0;
}
