shader_type spatial;
render_mode unshaded, cull_front, depth_draw_always;

uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_width = 0.045;
uniform float glow_strength = 1.0;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	// Opaque on purpose: writing ALPHA would put the shell in the transparent pass, where it
	// sorts against the room unpredictably (and the preview scene drops blended meshes entirely).
	ALBEDO = outline_color.rgb;
	EMISSION = outline_color.rgb * glow_strength;
}
