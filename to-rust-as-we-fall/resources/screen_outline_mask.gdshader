shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled;

// Per-object SCREEN-SPACE outline + queued energy glow. The highlighted objects are rendered ALONE into a
// SubViewport — each filled with its tint colour, on a transparent background (the "mask"). The fill ALPHA
// encodes intent: a HOVER object fills LOW alpha (outline only), a QUEUED one fills FULL alpha (outline + glow).
//   * Crisp outline = Sobel of the mask coverage. The mask is a flat solid, so its only edge is each object's
//     OUTER silhouette: gap-free, constant pixel width at any distance, immune to the geometry normals.
//   * Energy glow = a noise-MORPHED, pixel-DITHERED halo that radiates ONLY from the QUEUED (clicked) silhouette.
//     A screen-space DISTANCE FIELD (nearest queued pixel) drives the visibility, so the glow only appears
//     OUTSIDE the object, fades smoothly with distance from the edge, and stipples through an ordered 4x4 Bayer
//     dither (the same grammar as the hover grid / portal VFX). Hover shows the crisp outline only — no noise.
// Both read their colour straight from the mask, so several objects can carry different tints in one pass.
uniform sampler2D mask_tex : filter_linear;          // every highlighted object (drives the crisp outline)
uniform sampler2D glow_mask_tex : filter_linear;     // QUEUED objects only (drives the energy glow)
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float thickness : hint_range(0.5, 6.0, 0.1) = 2.0;
uniform float glow : hint_range(0.0, 4.0, 0.05) = 1.15;             // crisp-outline emission boost
uniform float glow_radius : hint_range(2.0, 64.0, 1.0) = 22.0;      // queued halo reach (px) = the SDF fade distance
uniform float glow_strength : hint_range(0.0, 6.0, 0.05) = 2.4;     // queued halo intensity
uniform float noise_scale : hint_range(0.2, 12.0, 0.1) = 3.0;       // halo noise frequency
uniform float noise_speed : hint_range(0.0, 1.0, 0.01) = 0.13;      // how fast the halo morphs
uniform float queued_threshold : hint_range(0.1, 1.0, 0.01) = 0.5;  // glow-mask coverage above this = inside a queued object
uniform bool flip_y = false;
uniform vec4 fallback_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Ordered 4x4 Bayer thresholds — the same matrix the hover grid + portal_dither use, so the glow stipples in the
// project's house dither style.
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

// Two scrolling samples of the noise multiplied -> a churning, morphing field (not a flat scroll), so the halo
// reads as living energy rather than a static blur.
float morph_noise(vec2 uv) {
	vec2 a = uv * noise_scale + vec2(TIME * noise_speed, TIME * noise_speed * 0.6);
	vec2 b = uv * noise_scale * 1.3 - vec2(TIME * noise_speed * 0.5, TIME * noise_speed * 0.9);
	return texture(noise_tex, a).r * texture(noise_tex, b).r;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 muv = flip_y ? vec2(uv.x, 1.0 - uv.y) : uv;
	vec2 inv = 1.0 / VIEWPORT_SIZE;
	vec2 px = thickness * inv;

	// --- crisp outline: Sobel of mask coverage (alpha) ---
	vec4 tl = texture(mask_tex, muv + px * vec2(-1.0,  1.0));
	vec4 tm = texture(mask_tex, muv + px * vec2( 0.0,  1.0));
	vec4 tr = texture(mask_tex, muv + px * vec2( 1.0,  1.0));
	vec4 ml = texture(mask_tex, muv + px * vec2(-1.0,  0.0));
	vec4 cc = texture(mask_tex, muv);
	vec4 mr = texture(mask_tex, muv + px * vec2( 1.0,  0.0));
	vec4 bl = texture(mask_tex, muv + px * vec2(-1.0, -1.0));
	vec4 bm = texture(mask_tex, muv + px * vec2( 0.0, -1.0));
	vec4 br = texture(mask_tex, muv + px * vec2( 1.0, -1.0));
	float gx = (tr.a + 2.0 * mr.a + br.a) - (tl.a + 2.0 * ml.a + bl.a);
	float gy = (tl.a + 2.0 * tm.a + tr.a) - (bl.a + 2.0 * bm.a + br.a);
	float edge = clamp(sqrt(gx * gx + gy * gy), 0.0, 1.0);
	// Outline colour = the most-covered neighbour's fill (the object's own tint).
	vec3 oc = fallback_color.rgb;
	float best = 0.0;
	if (cc.a > best) { best = cc.a; oc = cc.rgb; }
	if (tl.a > best) { best = tl.a; oc = tl.rgb; }
	if (tm.a > best) { best = tm.a; oc = tm.rgb; }
	if (tr.a > best) { best = tr.a; oc = tr.rgb; }
	if (ml.a > best) { best = ml.a; oc = ml.rgb; }
	if (mr.a > best) { best = mr.a; oc = mr.rgb; }
	if (bl.a > best) { best = bl.a; oc = bl.rgb; }
	if (bm.a > best) { best = bm.a; oc = bm.rgb; }
	if (br.a > best) { best = br.a; oc = br.rgb; }
	if (best <= 0.001) { oc = fallback_color.rgb; }

	// --- queued energy glow: a screen-space DISTANCE FIELD of the GLOW mask (queued objects ONLY) drives a
	// noise-dithered halo. March outward in a ring of directions to the NEAREST queued pixel; that distance is the
	// SDF. The glow mask is empty for a hover-only object, so HOVER produces no glow at all — structurally. ---
	float min_d = glow_radius + 1.0;
	vec3 gcol = oc;
	const int DIRS = 12;
	const int STEPS = 6;
	for (int i = 0; i < DIRS; i++) {
		float ang = float(i) / float(DIRS) * 6.2831853;
		vec2 dir = vec2(cos(ang), sin(ang));
		for (int s = 1; s <= STEPS; s++) {
			float rad = float(s) / float(STEPS) * glow_radius;
			vec4 smp = texture(glow_mask_tex, muv + dir * rad * inv);
			if (smp.a >= queued_threshold) {
				if (rad < min_d) { min_d = rad; gcol = smp.rgb; }
				break;   // nearest hit along this direction
			}
		}
	}
	float here_q = step(queued_threshold, texture(glow_mask_tex, muv).a);   // 1 inside a queued object
	// SDF visibility: bright at the silhouette (d=0), smooth fade to 0 at glow_radius, OUTSIDE the object only.
	float vis = (1.0 - here_q) * (1.0 - smoothstep(0.0, glow_radius, min_d));
	float n = morph_noise(muv);
	float energy = vis * (0.35 + 0.65 * n);                      // distance-faded, noise-broken energy field [0,1]
	// Pixel DITHER: stipple the glow where the energy strictly beats the ordered Bayer cell (project house style).
	float keep = (energy > bayer(FRAGCOORD.xy)) ? 1.0 : 0.0;
	float glow_amt = keep * energy * glow_strength;

	vec3 base = texture(screen_tex, uv).rgb;
	vec3 outline_rgb = mix(base, oc, edge);
	ALBEDO = outline_rgb + gcol * glow_amt;
	EMISSION = oc * edge * glow + gcol * glow_amt * 1.4;
}
