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
// The fill ALPHA doubles as a "should this object glow" flag the composite reads back: a HOVER object fills at a
// low alpha (outline only), a QUEUED one fills at full alpha (outline + energy glow). The Sobel saturates either
// way, so both still draw a crisp outline; only the glow halo keys off the high-alpha (queued) pixels.
uniform float fill_alpha : hint_range(0.0, 1.0, 0.01) = 1.0;

void fragment() {
	if (use_alpha) {
		if (texture(src_albedo, UV).a < cutoff) {
			discard;
		}
	}
	ALBEDO = fill_color.rgb;
	ALPHA = fill_alpha;
}
