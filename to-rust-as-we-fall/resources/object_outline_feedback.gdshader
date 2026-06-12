shader_type spatial;
render_mode unshaded, cull_front, depth_draw_always;

// Inverted-hull highlight shell. OPAQUE pass on purpose (a blended shell sorts unpredictably
// against the room and vanishes in the preview's dropped blend pass) — transparency is handled
// the way the opaque pipeline handles it: sample the SOURCE surface's albedo and DISCARD texels
// under the cutoff, so the outline hugs the visible silhouette (cutout foliage, glass screens)
// instead of the raw quad. Surfaces with no alpha keep a full hull.
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_width = 0.045;
uniform float glow_strength = 1.0;
uniform bool use_source_alpha = false;
uniform sampler2D source_albedo : source_color, filter_linear_mipmap;
uniform vec4 source_albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float alpha_cutoff = 0.35;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	if (use_source_alpha) {
		float source_alpha = texture(source_albedo, UV).a * source_albedo_tint.a;
		if (source_alpha < alpha_cutoff) {
			discard;
		}
	}
	ALBEDO = outline_color.rgb;
	EMISSION = outline_color.rgb * glow_strength;
}
