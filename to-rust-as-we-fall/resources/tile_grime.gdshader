shader_type spatial;

// Pixel-art tile atlas with PERLIN-VARIED DENSITY. The plain triplanar material tiles one 32px tile
// over and over at uniform density, which reads dead-flat. Here the crisp tile is sampled in OBJECT
// space (locked to the building, no swim under rotation), but a multi-scale value-noise field over
// WORLD position modulates it: broad grime patches darken + desaturate, the darkest cores bleed to
// rust, and a slow brightness field breaks the uniformity — so the same tile reads with varying wear
// density across a facade and from building to building. Cosmetic surface only.

uniform sampler2D tile_tex : filter_nearest, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float tiles_per_m = 1.0;
// Cells per side of a VARIATION ATLAS (1 = a plain single tile). With an 8x8 atlas
// one metre spans one CELL, so consecutive metres sample different hand-varied tiles
// instead of stamping the same 32px cell (the single-tile leopard-mottle fix).
uniform float atlas_cells = 1.0;
uniform vec4 grime_color : source_color = vec4(0.16, 0.13, 0.10, 1.0);
uniform float grime_amount = 0.58;
uniform vec4 rust_color : source_color = vec4(0.36, 0.18, 0.10, 1.0);
uniform float rust_amount = 0.42;
uniform float grime_scale = 0.16;    // 1/size of the broad grime patches (world metres)
uniform float roughness_val = 0.85;
uniform float emission_energy = 0.0; // opt-in low self-light for readable night-route surfaces

varying vec3 v_obj;      // object-space position (tile UVs — locked to the mesh)
varying vec3 v_world;    // world-space position (noise field — varies per building/facade)
varying vec3 v_nrm;      // object-space normal (triplanar blend)

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
	           mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

void vertex() {
	v_obj = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nrm = NORMAL;
}

void fragment() {
	// object-space triplanar tile sample (crisp, locked to the building)
	vec3 uv = v_obj * tiles_per_m / atlas_cells;
	vec3 bn = abs(normalize(v_nrm));
	bn /= (bn.x + bn.y + bn.z);
	vec3 cx = texture(tile_tex, uv.zy).rgb;
	vec3 cy = texture(tile_tex, uv.xz).rgb;
	vec3 cz = texture(tile_tex, uv.xy).rgb;
	vec3 base = cx * bn.x + cy * bn.y + cz * bn.z;

	// density-varying grime from a WORLD-space noise field (two octaves)
	float n_lo = vnoise(v_world * grime_scale);
	float n_hi = vnoise(v_world * (grime_scale * 3.4) + 11.0);
	float grime = smoothstep(0.42, 0.72, n_lo * 0.66 + n_hi * 0.34);
	base = mix(base, base * grime_color.rgb, grime * grime_amount);
	float rust = smoothstep(0.6, 0.9, n_lo);
	base = mix(base, rust_color.rgb, rust * rust_amount);
	base *= 0.9 + 0.28 * vnoise(v_world * (grime_scale * 0.5) + 31.0);

	vec3 final_color = base * tint.rgb;
	ALBEDO = final_color;
	EMISSION = final_color * emission_energy;
	ROUGHNESS = roughness_val;
}
