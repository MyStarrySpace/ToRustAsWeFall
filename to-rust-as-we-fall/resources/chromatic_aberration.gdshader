shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength_px = 5.0;
uniform float intensity = 1.0;
uniform float center_dead_zone = 0.06;
uniform float edge_start = 0.12;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 from_center = uv - vec2(0.5);
	float dist = length(from_center) * 1.41421356;
	float radial = smoothstep(center_dead_zone, 1.0, dist);
	float edge_weight = smoothstep(edge_start, 1.0, dist);
	vec2 direction = normalize(from_center + vec2(0.0001));
	vec2 offset = direction * SCREEN_PIXEL_SIZE * strength_px * radial * edge_weight;

	vec2 red_uv = clamp(uv + offset, SCREEN_PIXEL_SIZE, vec2(1.0) - SCREEN_PIXEL_SIZE);
	vec2 blue_uv = clamp(uv - offset, SCREEN_PIXEL_SIZE, vec2(1.0) - SCREEN_PIXEL_SIZE);
	vec3 base = texture(screen_tex, uv).rgb;
	vec3 split = vec3(
		texture(screen_tex, red_uv).r,
		base.g,
		texture(screen_tex, blue_uv).b
	);

	COLOR = vec4(mix(base, split, clamp(intensity, 0.0, 1.0)), 1.0);
}
