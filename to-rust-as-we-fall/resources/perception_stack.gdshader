shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

uniform bool data_enabled = false;
uniform vec3 data_character_pos = vec3(0.0);
uniform int data_vision_count = 1;
uniform vec3 data_vision_pos_1 = vec3(0.0);
uniform vec3 data_vision_pos_2 = vec3(0.0);
uniform float data_clear_radius = 14.0;
uniform float data_blend_width = 4.5;
uniform vec3 data_edge_color = vec3(0.29, 0.55, 0.85);
uniform float data_edge_width = 1.5;
uniform vec3 data_blackout_pos = vec3(0.0, 0.0, -9999.0);
uniform float data_blackout_radius = 0.0;
uniform float data_blackout_blend = 2.0;

uniform bool fog_enabled = false;
uniform vec3 fog_character_pos = vec3(0.0);
uniform int fog_vision_count = 1;
uniform vec3 fog_vision_pos_1 = vec3(0.0);
uniform vec3 fog_vision_pos_2 = vec3(0.0);
uniform float fog_clear_radius = 14.0;
uniform float fog_blend_width = 5.0;
uniform vec3 fog_color = vec3(0.15, 0.1, 0.07);
uniform float fog_desaturation = 0.8;

float vision_distance(vec3 world_pos, int source_count, vec3 primary_pos, vec3 secondary_pos, vec3 tertiary_pos) {
	float dist = distance(world_pos, primary_pos);
	if (source_count > 1) {
		dist = min(dist, distance(world_pos, secondary_pos));
	}
	if (source_count > 2) {
		dist = min(dist, distance(world_pos, tertiary_pos));
	}
	return dist;
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec3 current = texture(screen_tex, SCREEN_UV).rgb;

	float depth_raw = texture(depth_tex, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view_coords = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_coords.xyz /= view_coords.w;
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(view_coords.xyz, 1.0)).xyz;

	if (data_enabled) {
		float data_dist = vision_distance(world_pos, data_vision_count, data_character_pos, data_vision_pos_1, data_vision_pos_2);
		float data_blend = smoothstep(data_clear_radius, data_clear_radius + data_blend_width, data_dist);

		if (data_blend > 0.005) {
			vec2 ps = (1.0 / VIEWPORT_SIZE) * data_edge_width;

			float dl = texture(depth_tex, SCREEN_UV + vec2(-ps.x, 0.0)).r;
			float dr = texture(depth_tex, SCREEN_UV + vec2(ps.x, 0.0)).r;
			float du = texture(depth_tex, SCREEN_UV + vec2(0.0, -ps.y)).r;
			float dd = texture(depth_tex, SCREEN_UV + vec2(0.0, ps.y)).r;
			float gx = dl - dr;
			float gy = du - dd;
			float depth_edge = smoothstep(0.0002, 0.003, sqrt(gx * gx + gy * gy));

			vec3 cl = texture(screen_tex, SCREEN_UV + vec2(-ps.x, 0.0)).rgb;
			vec3 cr = texture(screen_tex, SCREEN_UV + vec2(ps.x, 0.0)).rgb;
			vec3 cu = texture(screen_tex, SCREEN_UV + vec2(0.0, -ps.y)).rgb;
			vec3 cd = texture(screen_tex, SCREEN_UV + vec2(0.0, ps.y)).rgb;
			float lum_c = dot(current, vec3(0.3, 0.59, 0.11));
			float lum_l = dot(cl, vec3(0.3, 0.59, 0.11));
			float lum_r = dot(cr, vec3(0.3, 0.59, 0.11));
			float lum_u = dot(cu, vec3(0.3, 0.59, 0.11));
			float lum_d = dot(cd, vec3(0.3, 0.59, 0.11));
			float color_edge = smoothstep(0.01, 0.08, abs(lum_l + lum_r + lum_u + lum_d - 4.0 * lum_c));

			float edge = clamp(max(depth_edge, color_edge * 0.6), 0.0, 1.0);
			vec3 data_view = vec3(0.01, 0.012, 0.02) + edge * data_edge_color;
			float scanline = 0.92 + 0.08 * sin(SCREEN_UV.y * VIEWPORT_SIZE.y * 0.3);
			data_view *= scanline;

			current = mix(current, data_view, data_blend);
		}

		if (data_blackout_radius > 0.0) {
			float blackout_dist = distance(world_pos, data_blackout_pos);
			float blackout = 1.0 - smoothstep(
				data_blackout_radius - data_blackout_blend,
				data_blackout_radius,
				blackout_dist
			);
			current = mix(current, vec3(0.005, 0.005, 0.01), blackout);
		}
	}

	if (fog_enabled) {
		float fog_dist = vision_distance(world_pos, fog_vision_count, fog_character_pos, fog_vision_pos_1, fog_vision_pos_2);
		float fog_blend = smoothstep(fog_clear_radius, fog_clear_radius + fog_blend_width, fog_dist);

		if (fog_blend > 0.005) {
			float lum = dot(current, vec3(0.3, 0.59, 0.11));
			vec3 desat = mix(current, vec3(lum), fog_desaturation * fog_blend);
			vec3 fogged = mix(desat, fog_color, fog_blend * 0.7);
			fogged = mix(fogged, vec3(dot(fogged, vec3(0.3, 0.59, 0.11))), fog_blend * 0.3);
			current = fogged;
		}
	}

	ALBEDO = current;
	ALPHA = 1.0;
}
