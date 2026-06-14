shader_type spatial;
// A flat 2D shape (a soft ring) that DITHERS in and out — the same ordered-Bayer stipple the hover
// grid uses, but animated by a `dissolve` uniform so the shape stipples away to nothing. Additive +
// unshaded so it reads as light in the dark room; screen-space dither keeps the dot size crisp and
// uniform regardless of the ground angle. Drawn on a PlaneMesh lying flat on the floor.
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.36, 0.91, 0.5, 1.0);
uniform float dissolve : hint_range(0.0, 1.2) = 0.0;  // 0 = gone, 1 = fully formed (animated)
uniform float ring_inner = 0.46;   // annulus radii in UV space (0 = centre, 1 = quad edge)
uniform float ring_outer = 0.66;
uniform float edge_soft = 0.10;    // soft band so the ring's own edges dither first
uniform float emission_energy = 3.2;

// Ordered 4x4 Bayer thresholds (same as the hover grid).
const float BAYER[16] = float[](
	0.0 / 16.0, 8.0 / 16.0, 2.0 / 16.0, 10.0 / 16.0,
	12.0 / 16.0, 4.0 / 16.0, 14.0 / 16.0, 6.0 / 16.0,
	3.0 / 16.0, 11.0 / 16.0, 1.0 / 16.0, 9.0 / 16.0,
	15.0 / 16.0, 7.0 / 16.0, 13.0 / 16.0, 5.0 / 16.0
);

float bayer(vec2 frag) {
	int x = int(mod(frag.x, 4.0));
	int y = int(mod(frag.y, 4.0));
	return BAYER[y * 4 + x];
}

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;  // 0 at centre, 1 at the quad edge
	// A soft-edged annulus: ramps up at ring_inner, ramps down at ring_outer, so the rim dithers out
	// before the core.
	float ring = smoothstep(ring_inner - edge_soft, ring_inner, r) * (1.0 - smoothstep(ring_outer, ring_outer + edge_soft, r));
	float presence = ring * dissolve;
	// Keep only where presence strictly beats the threshold (<= discards), so presence==0 outside the
	// ring always drops — even at the bayer==0 cell. Matches the hover grid's strict-> keep rule.
	if (presence <= bayer(FRAGCOORD.xy)) {
		discard;  // stippled away
	}
	ALBEDO = color.rgb;
	EMISSION = color.rgb * emission_energy;
}
