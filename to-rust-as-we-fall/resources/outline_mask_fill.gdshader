shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled, specular_disabled;

// Fills a highlighted object's silhouette with a flat TINT colour for the outline MASK (rendered into the
// OutlineMaskManager's SubViewport). Opaque, so the silhouette writes alpha 1 over the viewport's transparent
// (alpha 0) clear — the mask shader Sobels that alpha. For an alpha-cutout source (foliage, decals) we sample
// the source albedo's alpha and discard see-through texels, so the mask hugs the VISIBLE silhouette, not the
// full quad.
uniform vec4 fill_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D src_albedo : source_color, hint_default_white;
uniform bool use_alpha = false;
uniform float cutoff : hint_range(0.0, 1.0, 0.01) = 0.5;

void fragment() {
	if (use_alpha) {
		if (texture(src_albedo, UV).a < cutoff) {
			discard;
		}
	}
	ALBEDO = fill_color.rgb;
	ALPHA = 1.0;
}
