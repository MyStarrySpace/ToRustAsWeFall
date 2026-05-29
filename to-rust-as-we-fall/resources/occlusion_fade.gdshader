shader_type spatial;
// Dithered (stippled) transparency keeps occluders in the opaque pass, so there
// are no alpha-sorting artifacts on walls. Fragments inside a tube running from
// the camera to the player fade out, revealing the character behind geometry.
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// Player world position — the controller sets this every frame. Camera position
// is read from the view matrix, so the shader needs no camera uniform.
uniform vec3 player_position = vec3(0.0);

// Tube radius around the camera→player axis (world units) and its soft edge.
uniform float fade_radius : hint_range(0.05, 5.0) = 1.15;
uniform float fade_softness : hint_range(0.0, 2.0) = 0.6;
// Lowest visibility a fully-occluding fragment keeps (0 = vanish, 1 = solid).
uniform float min_visibility : hint_range(0.0, 1.0) = 0.1;
// Let fragments a little behind the player fade too, to avoid a hard pop.
uniform float player_depth_bias : hint_range(0.0, 2.0) = 0.5;

// Surface look, so this can stand in for a basic material without losing albedo.
uniform vec4 albedo_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.85;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// 4x4 ordered Bayer dither — stable per screen pixel, so the stipple does not
// crawl as the camera moves.
float bayer4x4(vec2 frag) {
	int x = int(mod(frag.x, 4.0));
	int y = int(mod(frag.y, 4.0));
	int index = x + y * 4;
	float m[16] = float[16](
		0.0,  8.0,  2.0, 10.0,
		12.0, 4.0, 14.0,  6.0,
		3.0, 11.0,  1.0,  9.0,
		15.0, 7.0, 13.0,  5.0
	);
	return (m[index] + 0.5) / 16.0;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV) * albedo_color;
	ALBEDO = tex.rgb;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;

	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_player = player_position - cam;
	float seg_len = length(to_player);

	float occ = 0.0;
	if (seg_len > 0.0001) {
		vec3 dir = to_player / seg_len;
		float t = dot(v_world - cam, dir);           // distance along the axis
		if (t > 0.0) {
			vec3 closest = cam + dir * clamp(t, 0.0, seg_len);
			float perp = length(v_world - closest);  // distance from the axis
			float radial = 1.0 - smoothstep(fade_radius, fade_radius + fade_softness, perp);
			// Only fade what is between the camera and (just past) the player.
			float depth_gate = 1.0 - smoothstep(seg_len, seg_len + player_depth_bias, t);
			occ = radial * depth_gate;
		}
	}

	float visibility = mix(1.0, min_visibility, occ);
	// Hashed/ordered dither: discard a fraction of pixels proportional to the
	// occlusion, leaving a stable stipple instead of true transparency.
	if (visibility < bayer4x4(FRAGCOORD.xy)) {
		discard;
	}
	ALPHA = 1.0;
}
