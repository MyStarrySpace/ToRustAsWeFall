shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled;

// Per-object SCREEN-SPACE outline + queued energy glow. The highlighted objects are rendered ALONE into a
// SubViewport — each filled with its tint colour, on a transparent background (the "mask"). The fill ALPHA
// encodes intent: a HOVER object fills LOW alpha (outline only), a QUEUED one fills FULL alpha (outline + glow).
//   * Crisp outline = Sobel of the mask coverage. The mask is a flat solid, so its only edge is each object's
//     OUTER silhouette: gap-free, constant pixel width at any distance, immune to the geometry normals.
//   * Energy glow = a soft, noise-MORPHED halo radiating from the QUEUED (high-alpha) pixels only — two scrolling
//     noise samples multiplied so it churns like shed energy (the same recipe as the old emission shell).
// Both read their colour straight from the mask, so several objects can carry different tints in one pass.
uniform sampler2D mask_tex : filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float thickness : hint_range(0.5, 6.0, 0.1) = 2.0;
uniform float glow : hint_range(0.0, 4.0, 0.05) = 1.15;             // crisp-outline emission boost
uniform float glow_radius : hint_range(2.0, 64.0, 1.0) = 22.0;      // queued halo reach (px)
uniform float glow_strength : hint_range(0.0, 6.0, 0.05) = 2.4;     // queued halo intensity
uniform float noise_scale : hint_range(0.2, 12.0, 0.1) = 3.0;       // halo noise frequency
uniform float noise_speed : hint_range(0.0, 1.0, 0.01) = 0.13;      // how fast the halo morphs
uniform float queued_threshold : hint_range(0.5, 1.0, 0.01) = 0.78; // alpha above this = "queued" (glows)
uniform bool flip_y = false;
uniform vec4 fallback_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
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

	// --- queued energy glow: a soft halo of the QUEUED (high-alpha) silhouette, morphed by noise ---
	float qsum = 0.0;
	float wsum = 0.0;
	vec3 gcol = vec3(0.0);
	for (int i = 0; i < 12; i++) {
		float ang = float(i) / 12.0 * 6.2831853;
		vec2 dir = vec2(cos(ang), sin(ang));
		for (int r = 1; r <= 2; r++) {
			float rad = glow_radius * (float(r) / 2.0);
			vec4 s = texture(mask_tex, muv + dir * rad * inv);
			float q = smoothstep(queued_threshold - 0.08, queued_threshold + 0.1, s.a);
			float w = 1.0 - (rad / glow_radius) * 0.45;
			qsum += q * w;
			wsum += w;
			gcol += s.rgb * q * w;
		}
	}
	float halo = (wsum > 0.0) ? qsum / wsum : 0.0;
	if (qsum > 0.001) {
		gcol = gcol / qsum;
	} else {
		gcol = oc;
	}
	float here_q = smoothstep(queued_threshold - 0.08, queued_threshold + 0.1, cc.a);
	float band = halo * (1.0 - here_q * 0.85);          // mostly OUTSIDE the solid (a radiating rim, not a face wash)
	float n = morph_noise(muv);
	float glow_amt = band * (0.12 + 0.88 * n) * glow_strength;   // noise breaks the band into shed energy

	vec3 base = texture(screen_tex, uv).rgb;
	vec3 outline_rgb = mix(base, oc, edge);
	ALBEDO = outline_rgb + gcol * glow_amt;
	EMISSION = oc * edge * glow + gcol * glow_amt * 1.4;
}
