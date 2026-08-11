shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

// One shared sight roster drives every fullscreen perception pass. The host fills this from its
// live character registry, so sight is not coupled to Aster, the active portrait, or a three-person
// launch roster. Positions live in a float data texture because that path is reliable on WebGL;
// sixty-four sources is far beyond the playable party while remaining a negligible 1D texture.
const int MAX_VISION_SOURCES = 64;
uniform int vision_source_count = 0;
uniform sampler2D vision_sources_tex : filter_nearest, repeat_disable;

uniform bool data_enabled = false;
uniform float data_clear_radius = 14.0;
uniform float data_blend_width = 4.5;
uniform vec3 data_edge_color = vec3(0.29, 0.55, 0.85);
uniform float data_edge_width = 1.5;
uniform vec3 data_blackout_pos = vec3(0.0, 0.0, -9999.0);
uniform float data_blackout_radius = 0.0;
uniform float data_blackout_blend = 2.0;

float depth_to_ndc(float depth_raw) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return depth_raw * 2.0 - 1.0;
#else
	return depth_raw;
#endif
}

// The stack's veil/edge colors are authored in LINEAR light — Forward+ tonemaps
// them into the intended warm parchment. The Compatibility renderer (and thus the
// WEB build) outputs sRGB directly, which displays raw linear values ~2.5x darker:
// the fog veil went near-black in the browser. Encode authored colors for the
// active pipeline so both renderers show the same veil.
vec3 pipe_color(vec3 linear_authored) {
	return OUTPUT_IS_SRGB ? pow(linear_authored, vec3(1.0 / 2.2)) : linear_authored;
}

// Line-of-sight: a fragment hidden behind a wall from every vision source reads as unseen (data-view / fog)
// even inside the clear radius, so the visibility hugs walls instead of being a flat circle. Screen-space:
// march the segment source->fragment, project each step, and compare the depth buffer. SOFTENED: it accumulates
// PARTIAL occlusion (a fade, not a binary cut) with a HEIGHT-AWARE tolerance (a small vertical step — stairs /
// ramps — is forgiven, a wall is not) and a DISTANCE FALLOFF so far occluders fade rather than hard-cut.
// Cosmetic (the player's perception view only).
uniform bool los_enabled = true;
uniform float los_bias = 0.65;           // base along-ray slack (floor/source self-occlusion)
uniform float los_step_tolerance = 1.0;  // EXTRA forgiveness scaled by vertical gap; > one ~0.72m elevation step so stairs/ramps don't read as walls
uniform float los_softness = 0.55;       // width of the soft occlusion band (fade, not a binary cut)
uniform float los_max_dist = 26.0;       // EXTENDED reach: occlusion is computed out to here
uniform float los_fade = 8.0;            // world-unit band over which distant occluders fade to no shadow before los_max_dist
uniform float los_occluder_gain = 1.6;   // lets a real (thin) wall reach full shadow without lowering the step tolerance

// BAKED OCCLUDER MASK: generated levels bake their sight-blocking cells into a small texture at
// chunk load (SightMaskBaker); when present, the LOS march samples IT bilinearly instead of
// reconstructing the depth buffer — cell silhouettes become smooth gradients, the march stops
// aliasing against props/creatures, and a small ring of vision-source taps adds a PENUMBRA so the
// fog edge rolls instead of stepping. Scenes without a grid keep the legacy depth-buffer path.
uniform bool occ_baked_enabled = false;
uniform sampler2D occ_tex : filter_linear, repeat_disable;
uniform vec2 occ_origin = vec2(0.0);
uniform float occ_cell = 1.5;
uniform vec2 occ_size = vec2(1.0);
uniform float los_penumbra = 0.85;   // source tap-ring radius (m) — the fog edge's softness

uniform bool fog_enabled = false;
uniform float fog_clear_radius = 14.0;
uniform float fog_blend_width = 5.0;
// Unseen ground is BLACK, and it has to land black on both pipelines. Authored colours are encoded
// for whichever renderer is active, which LIFTS a value as it encodes it -- 0.15 arrives near 0.42 on
// the sRGB path, a mid-tan the player reads as fog that glows. Authoring near zero survives the
// encode: dark stays dark either way, with just enough blue to read as depth rather than a dead pixel.
uniform vec3 fog_color = vec3(0.015, 0.015, 0.022);
uniform float fog_desaturation = 0.8;
uniform float los_thickness = 2.4;   // max depth gap for a sampled surface to count as CROSSING the ray

vec3 vision_source_at(int index) {
	return texelFetch(vision_sources_tex, ivec2(index, 0), 0).rgb;
}

// 1.0 = fully clear line of sight; 0.0 = fully blocked. SOFT: accumulates partial occlusion across the march
// with a HEIGHT-AWARE tolerance (a small vertical step is forgiven, a wall is not) and a DISTANCE FALLOFF so far
// occluders fade rather than hard-cut. Built-in matrices aren't visible in helpers, so they're passed in. Cosmetic.
float los_visible(vec3 src, vec3 world_pos, sampler2D depth, mat4 view, mat4 proj, mat4 inv_proj, mat4 inv_view, vec3 cam) {
	if (!los_enabled) { return 1.0; }

	const int STEPS = 24;                       // denser than before so thin occluders aren't skipped on the longer reach
	vec3 seg = world_pos - src;
	float seg_len = length(seg);
	if (seg_len < 0.0001) { return 1.0; }

	// EXTENDED reach with a fade: past los_max_dist nothing shadows; within los_fade of it the shadow falls off.
	float dist_fade = 1.0 - smoothstep(los_max_dist - los_fade, los_max_dist, seg_len);
	if (dist_fade <= 0.001) { return 1.0; }

	float occ = 0.0;                              // SOFT MAX of per-sample occlusion (a thin wall still fully blocks)
	float soft = max(los_softness, 0.0001);

	for (int i = 2; i < STEPS - 1; i++) {       // skip endpoints (source/fragment self-occlusion)
		float f = float(i) / float(STEPS);
		vec3 s = src + seg * f;

		vec4 clip = proj * view * vec4(s, 1.0);
		if (clip.w <= 0.0001) { continue; }
		vec2 suv = (clip.xy / clip.w) * 0.5 + 0.5;
		if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) { continue; }

		float raw = texture(depth, suv).x;
		vec4 vc = inv_proj * vec4(vec3(suv * 2.0 - 1.0, depth_to_ndc(raw)), 1.0);
		vc.xyz /= vc.w;
		vec3 w = (inv_view * vec4(vc.xyz, 1.0)).xyz;   // world point of the surface under this screen sample

		// Compare EXPECTED along-ray depth (the marched point) vs the SAMPLED surface depth, both as camera distance.
		float expected_depth = length(s - cam);
		float sampled_depth = length(w - cam);
		float intrusion = expected_depth - sampled_depth;   // >0 => a surface sits in front of the ray here

		// FOREGROUND-CLUTTER WINDOW: a surface metres in FRONT of the ray sits between the CAMERA and
		// the sightline (an arena's near boundary wall under a zoomed-out camera), not across it — it
		// cannot block sight between two points behind it. Only a surface NEAR the ray's own depth is
		// a real crossing occluder. Without this, any level enclosed by walls fogged to black whenever
		// the near wall entered the frame.
		if (intrusion > los_thickness) { continue; }

		// HEIGHT-AWARE forgiveness for STEPS, the right way for a top-down camera: a stair/ramp riser barely rises
		// above the sight ray, while a WALL towers over it. So forgive an occluder only when its sampled surface is
		// LOW relative to the ray (a step), and stay strict (base bias) when it rises well above (a wall). NOTE this
		// is the inverse of "widen tolerance with the vertical gap" — viewed from above a wall's nearest surface is
		// its HIGH top edge, so a gap-based widen wrongly forgives walls.
		float height_above = w.y - s.y;
		float wallness = smoothstep(los_step_tolerance, los_step_tolerance + 0.8, height_above);  // 0 = low step, 1 = wall
		float tol = los_bias + los_step_tolerance * (1.0 - wallness);

		// SOFT per sample (a grazing intrusion contributes a little; a deep one ~1) — smooth in intrusion so adjacent
		// fragments fade rather than flip (no blotch). Combine by MAX: a single solid occluder blocks even if it
		// only covers a few samples of the march (averaging diluted a thin wall to a faint smudge).
		occ = max(occ, smoothstep(tol, tol + soft, intrusion));
	}

	occ = clamp(occ * los_occluder_gain, 0.0, 1.0);    // push a real (even thin) wall to full shadow; steps stay ~0
	occ *= dist_fade;                                   // distant occluders fade out
	return clamp(1.0 - occ, 0.0, 1.0);                 // 1 = clear, partial = grazing step, 0 = wall
}

float occ_sample(vec2 xz) {
	vec2 uv = ((xz - occ_origin) / occ_cell) / occ_size;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) { return 0.0; }
	return texture(occ_tex, uv).r;
}

// One march through the baked mask. Endpoints skipped: the source stands in a doorway's bilinear
// bleed and the fragment's floor cell borders its own walls — neither should self-shadow.
float los_baked_single(vec3 src, vec3 world_pos) {
	float seg_len = length(world_pos - src);
	float dist_fade = 1.0 - smoothstep(los_max_dist - los_fade, los_max_dist, seg_len);
	if (dist_fade <= 0.001) { return 1.0; }
	const int STEPS = 18;
	vec2 a = src.xz;
	vec2 b = world_pos.xz;
	float occ = 0.0;
	for (int i = 1; i < STEPS - 1; i++) {
		occ = max(occ, occ_sample(mix(a, b, float(i) / float(STEPS))));
	}
	// the bilinear gradient (one cell wide) becomes the soft shadow ramp
	occ = smoothstep(0.18, 0.75, occ);
	return 1.0 - occ * dist_fade;
}

// PENUMBRA: average a ring of source taps, each weighted by how clear its own cell is (a tap
// displaced into a wall must not vote, or standing beside a wall would dim the whole view).
float los_baked(vec3 src, vec3 world_pos) {
	float total = los_baked_single(src, world_pos);
	float wsum = 1.0;
	vec2 ring[3] = vec2[](vec2(1.0, 0.0), vec2(-0.5, 0.866), vec2(-0.5, -0.866));
	for (int i = 0; i < 3; i++) {
		vec3 tap = src + vec3(ring[i].x, 0.0, ring[i].y) * los_penumbra;
		float w = 1.0 - occ_sample(tap.xz);
		if (w <= 0.01) { continue; }
		total += los_baked_single(tap, world_pos) * w;
		wsum += w;
	}
	return total / wsum;
}

// PENUMBRA for the depth-marched path, so a warped scene's fog edge rolls the way a flat scene's
// does. The baked path averages a ring of source taps; the depth path has no occluder mask to
// weight taps with, so a tap standing inside a wall cannot be told from one in the open. Taking the
// MOST visible tap sidesteps that: a buried tap reads occluded and simply loses, and the shadow
// edge softens by the ring radius instead of stair-stepping along whatever silhouette the depth
// buffer caught. Fully visible fragments return on the centre ray alone and pay nothing extra.
float los_depth(vec3 src, vec3 world_pos, sampler2D depth, mat4 view, mat4 proj, mat4 inv_proj, mat4 inv_view, vec3 cam) {
	float vis = los_visible(src, world_pos, depth, view, proj, inv_proj, inv_view, cam);
	if (los_penumbra <= 0.001 || vis >= 0.999) { return vis; }
	vec2 ring[3] = vec2[](vec2(1.0, 0.0), vec2(-0.5, 0.866), vec2(-0.5, -0.866));
	for (int i = 0; i < 3; i++) {
		vec3 tap = src + vec3(ring[i].x, 0.0, ring[i].y) * los_penumbra;
		vis = max(vis, los_visible(tap, world_pos, depth, view, proj, inv_proj, inv_view, cam));
		if (vis >= 0.999) { break; }
	}
	return vis;
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec3 current = texture(screen_tex, SCREEN_UV).rgb;

	float depth_raw = texture(depth_tex, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_to_ndc(depth_raw));
	vec4 view_coords = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_coords.xyz /= view_coords.w;
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(view_coords.xyz, 1.0)).xyz;

	if (data_enabled) {
		float data_blend = 1.0;
		for (int i = 0; i < MAX_VISION_SOURCES; i++) {
			if (i >= vision_source_count) { break; }
			vec3 src = vision_source_at(i);
			float source_blend = smoothstep(data_clear_radius, data_clear_radius + data_blend_width, distance(world_pos, src));
			// A farther source cannot improve an already-clearer distance result. If the nearer
			// source is occluded, however, another character still gets a chance to see the point.
			if (source_blend >= data_blend) { continue; }
			if (los_enabled && source_blend < 0.999) {
				float vis = occ_baked_enabled
					? los_baked(src, world_pos)
					: los_depth(src, world_pos, depth_tex, VIEW_MATRIX, PROJECTION_MATRIX, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, INV_VIEW_MATRIX[3].xyz);
				source_blend = max(source_blend, 1.0 - vis);
			}
			data_blend = min(data_blend, source_blend);
			if (data_blend <= 0.001) { break; }
		}

		if (data_blend > 0.005) {
			vec2 ps = (1.0 / VIEWPORT_SIZE) * data_edge_width;

			float dl = texture(depth_tex, SCREEN_UV + vec2(-ps.x, 0.0)).r;
			float dr = texture(depth_tex, SCREEN_UV + vec2(ps.x, 0.0)).r;
			float du = texture(depth_tex, SCREEN_UV + vec2(0.0, -ps.y)).r;
			float dd = texture(depth_tex, SCREEN_UV + vec2(0.0, ps.y)).r;
			float gx = dl - dr;
			float gy = du - dd;
			float depth_edge = smoothstep(0.0002, 0.003, sqrt(gx * gx + gy * gy));

			vec3 cl = texture(screen_tex, SCREEN_UV + vec2(-ps.x, 0.0)).rgb;
			vec3 cr = texture(screen_tex, SCREEN_UV + vec2(ps.x, 0.0)).rgb;
			vec3 cu = texture(screen_tex, SCREEN_UV + vec2(0.0, -ps.y)).rgb;
			vec3 cd = texture(screen_tex, SCREEN_UV + vec2(0.0, ps.y)).rgb;
			float lum_c = dot(current, vec3(0.3, 0.59, 0.11));
			float lum_l = dot(cl, vec3(0.3, 0.59, 0.11));
			float lum_r = dot(cr, vec3(0.3, 0.59, 0.11));
			float lum_u = dot(cu, vec3(0.3, 0.59, 0.11));
			float lum_d = dot(cd, vec3(0.3, 0.59, 0.11));
			float color_edge = smoothstep(0.01, 0.08, abs(lum_l + lum_r + lum_u + lum_d - 4.0 * lum_c));

			float edge = clamp(max(depth_edge, color_edge * 0.6), 0.0, 1.0);
			vec3 data_view = pipe_color(vec3(0.01, 0.012, 0.02)) + edge * pipe_color(data_edge_color);
			float scanline = 0.92 + 0.08 * sin(SCREEN_UV.y * VIEWPORT_SIZE.y * 0.3);
			data_view *= scanline;

			current = mix(current, data_view, data_blend);
		}

		if (data_blackout_radius > 0.0) {
			float blackout_dist = distance(world_pos, data_blackout_pos);
			float blackout = 1.0 - smoothstep(
				data_blackout_radius - data_blackout_blend,
				data_blackout_radius,
				blackout_dist
			);
			current = mix(current, pipe_color(vec3(0.005, 0.005, 0.01)), blackout);
		}
	}

	if (fog_enabled) {
		float fog_blend = 1.0;
		for (int i = 0; i < MAX_VISION_SOURCES; i++) {
			if (i >= vision_source_count) { break; }
			vec3 src = vision_source_at(i);
			float source_blend = smoothstep(fog_clear_radius, fog_clear_radius + fog_blend_width, distance(world_pos, src));
			if (source_blend >= fog_blend) { continue; }
			if (los_enabled && source_blend < 0.999) {
				float vis = occ_baked_enabled
					? los_baked(src, world_pos)
					: los_depth(src, world_pos, depth_tex, VIEW_MATRIX, PROJECTION_MATRIX, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, INV_VIEW_MATRIX[3].xyz);
				source_blend = max(source_blend, 1.0 - vis);
			}
			fog_blend = min(fog_blend, source_blend);
			if (fog_blend <= 0.001) { break; }
		}

		if (fog_blend > 0.005) {
			// Unseen ground reaches the fog colour, which is authored nearly black. Holding part of
			// the scene back at full blend leaves a lit deck showing through as a pale wash -- the
			// map stays legible exactly where it is supposed to be hidden, and a bright floor fogs
			// LIGHTER than a dark one. The ramp still rolls: partial blend is partial fog.
			float lum = dot(current, vec3(0.3, 0.59, 0.11));
			vec3 desat = mix(current, vec3(lum), fog_desaturation * fog_blend);
			current = mix(desat, pipe_color(fog_color), fog_blend);
		}
	}

	ALBEDO = current;
	ALPHA = 1.0;
}
