// Portal lens: the whole circular Portal_Surface disc shows the connected room.
// The SubViewport renders Monos's room from a camera mirrored through the portal
// (same FOV/aspect as the live camera), so sampling with SCREEN_UV makes the disc
// read as a true opening — parallax included — rather than a pasted picture.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D view_texture: source_color, filter_linear, repeat_disable;
uniform vec3 tint: source_color = vec3(1.0, 1.0, 1.0);

void fragment() {
	vec3 col = texture(view_texture, SCREEN_UV).rgb;
	ALBEDO = col * tint;
}
