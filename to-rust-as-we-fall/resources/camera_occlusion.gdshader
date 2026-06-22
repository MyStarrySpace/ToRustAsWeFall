shader_type spatial;
render_mode depth_draw_opaque, cull_back;

// "See-through level" occlusion, done in WORLD SPACE off the camera->player VECTOR (not a screen-projected
// circle, which was fragile and put the hole in the wrong place). Each fragment is tested against the line
// segment from the camera to the watched character: if it lies BETWEEN them and within a cone around that
// line (narrow at the camera, widening to the player), it dither-dissolves — so whatever is between the
// camera and the character is cut away and the character shows through. Driven by ONE global uniform
// (player_world_pos) the CameraOcclusionManager writes each frame; the camera position is the built-in
// CAMERA_POSITION_WORLD. The wrap copies albedo/emission/normal/roughness/metallic so the look survives.

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

// Reveal cone tuning (world units). radius grows from reveal_radius*min_factor at the camera to
// reveal_radius at the player, so the tunnel hugs the camera->player line and opens onto the character.
uniform float reveal_radius : hint_range(0.0, 8.0) = 3.5;
uniform float reveal_min_factor : hint_range(0.0, 1.0) = 0.5;
uniform float reveal_softness : hint_range(0.0, 1.0) = 0.65;   // fraction of the radius that feathers (dither band)
uniform float reveal_strength : hint_range(0.0, 1.0) = 1.0;    // 0 => occlusion disabled for this material
// Surfaces facing UP more steeply than this (the FLOOR/deck the player stands on) are NEVER cut — otherwise the
// cone punches a hole in the ground around the player's feet. Only WALLS / overhead structure get cut away.
uniform float floor_skip_cutoff : hint_range(0.0, 1.0) = 0.55;

varying vec3 v_world;          // fragment position in WORLD space
varying vec3 v_world_normal;   // world-space surface normal (used to leave the floor uncut)

const float BAYER4[16] = float[](
	 0.0 / 16.0,  8.0 / 16.0,  2.0 / 16.0, 10.0 / 16.0,
	12.0 / 16.0,  4.0 / 16.0, 14.0 / 16.0,  6.0 / 16.0,
	 3.0 / 16.0, 11.0 / 16.0,  1.0 / 16.0,  9.0 / 16.0,
	15.0 / 16.0,  7.0 / 16.0, 13.0 / 16.0,  5.0 / 16.0
);

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	ALBEDO = (texture(albedo_tex, UV) * albedo_color).rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = texture(emission_tex, UV).rgb * emission_color.rgb * emission_energy;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_scale;

	// GDShader forbids `return` in fragment(); the gates are NESTED ifs (discard IS allowed). Skip up-facing
	// FLOOR surfaces entirely so the cone never punches a hole in the ground under the player — only walls and
	// overhead structure get cut away.
	if (reveal_strength > 0.001 && v_world_normal.y < floor_skip_cutoff) {
		vec3 cam = CAMERA_POSITION_WORLD;
		vec3 to_player = player_world_pos - cam;
		float player_dist = length(to_player);
		if (player_dist > 0.05) {
			vec3 dir = to_player / player_dist;
			float t = dot(v_world - cam, dir);   // how far along the camera->player line this fragment projects
			// Only fragments BETWEEN the camera and the player (just short of the player) can occlude it.
			if (t > 0.1 && t < player_dist - 0.1) {
				vec3 closest = cam + dir * t;
				float perp = length(v_world - closest);                  // distance from the camera->player line
				float radius = reveal_radius * mix(reveal_min_factor, 1.0, t / player_dist);  // cone, wider at the player
				float reveal = (1.0 - smoothstep(radius * (1.0 - reveal_softness), radius, perp)) * reveal_strength;
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
}
