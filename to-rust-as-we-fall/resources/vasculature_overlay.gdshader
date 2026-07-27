shader_type spatial;
// The organic VASCULATURE overgrowth (concept plate C), applied as a per-instance
// material_overlay pass OVER the painted iron — so the drum/wall keep their base
// detail and the veins + glowing clusters lay on top, no rebuild, no z-fighting.
// World-space TRIPLANAR so it wraps the cylinders/walls without any UV setup, at a
// consistent real-world scale. ALPHA-SCISSOR (opaque, alpha-tested) not alpha-blend:
// the drum is stacked ngon segments, and blended overlays sort wrong on the compat/
// web renderer (horizontal ghost banding). Scissor is opaque — no sorting, crisp
// pixel-art vein edges, and the base iron shows through the discarded cut-away.
render_mode cull_back, diffuse_burley;

uniform sampler2D vein_albedo : source_color, filter_linear, repeat_enable;
uniform sampler2D vein_emissive : source_color, filter_linear, repeat_enable;
uniform sampler2D vein_normal : hint_normal, filter_linear, repeat_enable;
uniform float tiles_per_m = 0.32;      // vasculature scale (cells ~3 m across)
uniform float emission_energy = 2.6;
uniform float coverage = 1.0;          // global vein density fade
uniform float normal_depth = 1.2;

varying vec3 v_world;
varying vec3 v_nrm;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nrm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 bn = abs(normalize(v_nrm));
	bn /= (bn.x + bn.y + bn.z);
	vec2 uvx = v_world.zy * tiles_per_m;
	vec2 uvy = v_world.xz * tiles_per_m;
	vec2 uvz = v_world.xy * tiles_per_m;
	vec4 a = texture(vein_albedo, uvx) * bn.x + texture(vein_albedo, uvy) * bn.y + texture(vein_albedo, uvz) * bn.z;
	vec3 e = texture(vein_emissive, uvx).rgb * bn.x + texture(vein_emissive, uvy).rgb * bn.y + texture(vein_emissive, uvz).rgb * bn.z;
	vec3 nm = texture(vein_normal, uvx).rgb * bn.x + texture(vein_normal, uvy).rgb * bn.y + texture(vein_normal, uvz).rgb * bn.z;
	ALBEDO = a.rgb;
	ALPHA = clamp(a.a * coverage, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.42;   // opaque alpha-test: no transparency sorting
	EMISSION = e * emission_energy;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = normal_depth;
	ROUGHNESS = 0.5;
	METALLIC = 0.2;
}
