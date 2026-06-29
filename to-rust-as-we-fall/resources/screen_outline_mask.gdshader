shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled;

// Per-object SCREEN-SPACE outline. The highlighted objects are rendered ALONE into a SubViewport — each filled
// with its own tint colour, opaque (alpha 1) on a transparent (alpha 0) background. That render is the "mask".
// Sobel the mask's COVERAGE (alpha), so the only edge is each object's OUTER silhouette: no internal panel
// detail, no flat-shading tearing (it never touches the geometry's normals), constant pixel width at any
// distance, and inherently limited to the masked objects. The outline colour is read back from the mask, so
// several objects can carry DIFFERENT tints (hover = white, a queued interaction = the servicing char's colour)
// in one pass. EMISSION makes it read as a glow.
uniform sampler2D mask_tex : filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float thickness : hint_range(0.5, 6.0, 0.1) = 2.0;
uniform float glow : hint_range(0.0, 4.0, 0.05) = 1.5;
uniform bool flip_y = false;   // flip the mask V if the SubViewport texture is inverted vs the screen
uniform vec4 fallback_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 muv = flip_y ? vec2(uv.x, 1.0 - uv.y) : uv;
	vec2 px = thickness / VIEWPORT_SIZE;
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

	// Outline colour = the most-covered neighbour's fill (the object's own tint). Falls back when the mask
	// carried no colour at this pixel.
	vec3 col = fallback_color.rgb;
	float best = 0.0;
	if (cc.a > best) { best = cc.a; col = cc.rgb; }
	if (tl.a > best) { best = tl.a; col = tl.rgb; }
	if (tm.a > best) { best = tm.a; col = tm.rgb; }
	if (tr.a > best) { best = tr.a; col = tr.rgb; }
	if (ml.a > best) { best = ml.a; col = ml.rgb; }
	if (mr.a > best) { best = mr.a; col = mr.rgb; }
	if (bl.a > best) { best = bl.a; col = bl.rgb; }
	if (bm.a > best) { best = bm.a; col = bm.rgb; }
	if (br.a > best) { best = br.a; col = br.rgb; }
	if (best <= 0.001) { col = fallback_color.rgb; }

	vec3 base = texture(screen_tex, uv).rgb;
	ALBEDO = mix(base, col, edge);
	EMISSION = col * edge * glow;
}
