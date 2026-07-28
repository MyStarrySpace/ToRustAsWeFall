shader_type spatial;
// TRANSLUCENT water (blend_mix) — but it must also survive the perception overlay. A transparent surface is
// excluded from Godot's screen/depth textures (hint_screen_texture/hint_depth_texture), so the overlay's
// screen-space post-process (which rewrites the scene from those) draws right over it and the flood vanishes
// in data-view. The fix is RENDER ORDER, not opacity: the water material's render_priority is set ABOVE the
// overlay quad's (in _make_water_material) so the translucent water draws AFTER the overlay in the transparent
// pass and blends on top — visible in normal AND overlay modes while keeping its translucency + fresnel.
render_mode blend_mix, cull_disabled, depth_draw_opaque, diffuse_burley;

// Animated FLOOD-WATER surface for the channels (flooded Sector 12). The brightness comes from the BASE
// colours + a strong self-EMISSION (so it reads as glowing teal water in the dark drainage) — the dark
// pixel-art tile is used only for RIPPLE detail, never to darken the colour toward black (the earlier bug:
// dark tile x dark tint x luminance-scaled emission summed to near-invisible). Two world-space scroll
// layers + a sine warp animate the surface on engine TIME; a fresnel + crest band lays foam. Purely
// COSMETIC (@rendering_only): animates on shader TIME, never gates game state. GDShader forbids `return`
// in fragment()/vertex().

uniform sampler2D water_tex : source_color, filter_nearest, repeat_enable, hint_default_white;
uniform vec3 shallow_color : source_color = vec3(0.22, 0.74, 0.88);  // lit teal crest water
uniform vec3 deep_color : source_color = vec3(0.06, 0.34, 0.48);     // iron-teal trough (still readable)
uniform vec3 foam_color : source_color = vec3(0.78, 0.98, 1.0);      // crest / edge foam
uniform float flow_speed = 0.15;       // UV scroll along the flow dir, per second
uniform float flow_dir_x = 1.0;
uniform float flow_dir_y = 0.2;
uniform float tex_scale = 0.5;         // world-space tile repeat (smaller = bigger tiles)
uniform float warp_amount = 0.05;      // sine UV warp depth (the living wobble)
uniform float warp_speed = 0.9;
uniform float ripple_gain : hint_range(0.5, 4.0) = 2.2;     // remaps the dark tile into a usable 0..1 ripple
uniform float foam_strength : hint_range(0.0, 2.0) = 0.8;
uniform float water_alpha : hint_range(0.0, 1.0) = 0.88;    // translucency (see the deck faintly through it)
uniform float emission_strength : hint_range(0.0, 4.0) = 2.2;  // self-glow — what makes the flood READ
uniform float fresnel_strength : hint_range(0.0, 2.0) = 0.55;  // grazing-angle brightening — water
uniform float fresnel_power : hint_range(1.0, 8.0) = 3.0;      // read as a SURFACE, not a flat decal

// VISIBLE-RANGE fade (shared globals the perception view sets). A transparent surface is excluded from the
// perception overlay's screen rewrite, so it can't be data-viewed like opaque geometry — the flood would stay
// fully visible in the unseen, fogged distance. So when a perception view is active, the water fades its OWN
// alpha out past the clear radius around the nearest vision source. It reads the same data texture as the
// fullscreen pass, so future party members reveal transparent surfaces too. Off (no overlay) => fully visible.
const int MAX_VISION_SOURCES = 64;
global uniform bool visible_range_active;
global uniform int vision_source_count;
global uniform sampler2D vision_sources_tex;
global uniform float vision_clear_radius;
global uniform float vision_blend_width;
global uniform vec3 player_world_pos;

// When water on an UPPER helix turn falls directly between the camera and the active character, soften
// only that overhead fragment corridor. A non-zero alpha/emission floor keeps it visibly teal as a real
// hazard; water on the player's own turn is below the cut plane and remains completely unchanged.
uniform float reveal_radius : hint_range(0.0, 12.0) = 6.0;
uniform float reveal_min_factor : hint_range(0.0, 1.0) = 0.45;
uniform float reveal_softness : hint_range(0.0, 1.0) = 0.7;
uniform float reveal_alpha_floor : hint_range(0.0, 1.0) = 0.14;
uniform float reveal_emission_floor : hint_range(0.0, 1.0) = 0.2;
uniform float reveal_cut_above_player : hint_range(-2.0, 8.0) = 1.8;

varying vec3 v_world;
varying vec3 v_normal;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float t = TIME;
	vec2 fdir = normalize(vec2(flow_dir_x, flow_dir_y) + vec2(0.0001));
	// World-XZ projected UVs so the tile repeats in WORLD space (lines up across the segmented flood boxes).
	vec2 base_uv = v_world.xz * tex_scale;
	vec2 warp = vec2(sin(base_uv.y * 3.0 + t * warp_speed), cos(base_uv.x * 3.0 + t * warp_speed * 1.2)) * warp_amount;
	vec2 uv_a = base_uv + warp + fdir * (t * flow_speed);
	vec2 uv_b = base_uv * 1.6 - warp * 0.6 + fdir.yx * (-t * flow_speed * 0.7);
	// Ripple field from the tile luminance, gained UP into a usable 0..1 (the tile is intentionally dark).
	float ra = dot(texture(water_tex, uv_a).rgb, vec3(0.299, 0.587, 0.114));
	float rb = dot(texture(water_tex, uv_b).rgb, vec3(0.299, 0.587, 0.114));
	float ripple = clamp(mix(ra, rb, 0.45) * ripple_gain, 0.0, 1.0);

	// Base colour interpolates BRIGHT shallow over deep by the ripple — never multiplied toward black.
	vec3 col = mix(deep_color, shallow_color, ripple);

	// Foam: fresnel rim at grazing angles + the bright crests.
	float fres = pow(clamp(1.0 - abs(dot(normalize(v_normal), normalize(VIEW))), 0.0, 1.0), 3.0);
	float crest = smoothstep(0.6, 0.9, ripple);
	float foam = clamp(fres * 0.5 + crest * 0.8, 0.0, 1.0) * foam_strength;
	col = mix(col, foam_color, clamp(foam, 0.0, 1.0));

	// Fade the flood out beyond the visible range (nearest vision source) when a perception view is active,
	// so the water doesn't show in the unseen distance where opaque geometry is already data-viewed/fogged.
	float vis = 1.0;
	if (visible_range_active) {
		vis = 0.0;
		float d = 1e20;
		for (int i = 0; i < MAX_VISION_SOURCES; i++) {
			if (i >= vision_source_count) { break; }
			vec3 source_pos = texelFetch(vision_sources_tex, ivec2(i, 0), 0).rgb;
			d = min(d, distance(v_world, source_pos));
		}
		if (vision_source_count > 0) {
			vis = 1.0 - smoothstep(vision_clear_radius, vision_clear_radius + vision_blend_width, d);
		}
	}

	float camera_reveal = 0.0;
	if (v_world.y > player_world_pos.y + reveal_cut_above_player) {
		vec3 cam = CAMERA_POSITION_WORLD;
		vec3 to_player = player_world_pos - cam;
		float player_dist = length(to_player);
		if (player_dist > 0.05) {
			vec3 dir = to_player / player_dist;
			float along = dot(v_world - cam, dir);
			if (along > 0.1 && along < player_dist - 0.1) {
				vec3 closest = cam + dir * along;
				float perpendicular = length(v_world - closest);
				float radius = reveal_radius * mix(reveal_min_factor, 1.0, along / player_dist);
				camera_reveal = 1.0 - smoothstep(radius * (1.0 - reveal_softness), radius, perpendicular);
			}
		}
	}
	float reveal_alpha = mix(1.0, reveal_alpha_floor, camera_reveal);
	float reveal_emission = mix(1.0, reveal_emission_floor, camera_reveal);

	// FRESNEL: edge-on view brightens toward foam — the subtle surface response the
	// flat decal look lacked. Cheap scalar; identical on Forward+ and compat.
	// (edge_fres, distinct from the foam-band `fres` declared above.)
	float edge_fres = pow(1.0 - clamp(dot(normalize(v_normal), normalize(CAMERA_POSITION_WORLD - v_world)), 0.0, 1.0), fresnel_power) * fresnel_strength;
	col = mix(col, foam_color, clamp(edge_fres, 0.0, 0.6));
	ALBEDO = col;
	ROUGHNESS = 0.18;
	METALLIC = 0.0;
	// the ripple texture MODULATES the glow — at full flood a flat emission
	// washed every ripple out and the water photographed as a plastic slab
	EMISSION = col * (0.55 + 0.45 * ripple) * emission_strength * vis * reveal_emission;
	ALPHA = clamp((water_alpha + foam * 0.1) * vis * reveal_alpha, 0.0, 1.0);
}
