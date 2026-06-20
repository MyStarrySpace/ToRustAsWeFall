shader_type spatial;
render_mode depth_draw_opaque, cull_back;

// "See-through level" occlusion. Geometry that sits BETWEEN the camera and the watched character
// dither-dissolves in a circle around that character on screen, so the player is never lost behind a
// wall. The hole is a Bayer STIPPLE (the same pixel-dither grammar as the hover grid) rather than a
// smooth fade. Driven by ONE global uniform set per frame by CameraOcclusionManager — every wrapped
// material reads it. The wrap copies albedo / emission / normal / roughness / metallic from the source
// StandardMaterial3D, so the level's look (including the emissive glow) survives the shader swap.

global uniform vec3 player_world_pos;

uniform sampler2D albedo_tex : source_color, filter_nearest, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D emission_tex : source_color, filter_nearest, hint_default_black;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 1.0;
uniform sampler2D normal_tex : filter_nearest, hint_normal;
uniform float normal_scale : hint_range(-1.0, 1.0) = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

// Reveal tuning (per material; the manager leaves the defaults).
uniform float reveal_radius : hint_range(0.0, 0.6) = 0.14;     // screen-space radius (fraction of height)
uniform float reveal_softness : hint_range(0.0, 0.3) = 0.05;
uniform float reveal_strength : hint_range(0.0, 1.0) = 1.0;    // 0 => occlusion disabled for this material

varying vec3 v_view;   // fragment position in view space (to compare depth against the player)

// 4x4 ordered (Bayer) dither — same pixel-dither look as the hover grid.
const float BAYER4[16] = float[](
	 0.0 / 16.0,  8.0 / 16.0,  2.0 / 16.0, 10.0 / 16.0,
	12.0 / 16.0,  4.0 / 16.0, 14.0 / 16.0,  6.0 / 16.0,
	 3.0 / 16.0, 11.0 / 16.0,  1.0 / 16.0,  9.0 / 16.0,
	15.0 / 16.0,  7.0 / 16.0, 13.0 / 16.0,  5.0 / 16.0
);

void vertex() {
	v_view = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 base = texture(albedo_tex, UV) * albedo_color;
	ALBEDO = base.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = texture(emission_tex, UV).rgb * emission_color.rgb * emission_energy;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_scale;

	// GDShader forbids `return` in fragment(), so the gates are NESTED ifs (discard IS allowed).
	if (reveal_strength > 0.001) {
		vec3 player_view = (VIEW_MATRIX * vec4(player_world_pos, 1.0)).xyz;
		vec4 pclip = PROJECTION_MATRIX * vec4(player_view, 1.0);
		// View space looks down -Z, so a LARGER z is CLOSER to the camera: only fragments closer than the
		// player (between the camera and the player) can hide it, and only when the player is on screen.
		if (v_view.z > player_view.z + 0.05 && pclip.w > 0.0) {
			vec2 puv = pclip.xy / pclip.w * 0.5 + 0.5;
			puv.y = 1.0 - puv.y;   // clip-space Y is up; SCREEN_UV is top-left origin
			float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
			vec2 d = SCREEN_UV - puv;
			d.x *= aspect;   // keep the reveal a CIRCLE, not an ellipse
			float dist = length(d);
			float reveal = (1.0 - smoothstep(reveal_radius - reveal_softness, reveal_radius, dist)) * reveal_strength;
			if (reveal > 0.0) {
				int bx = int(FRAGCOORD.x) & 3;
				int by = int(FRAGCOORD.y) & 3;
				if (reveal > BAYER4[by * 4 + bx]) {
					discard;   // punch a dithered hole so the character shows through
				}
			}
		}
	}
}
