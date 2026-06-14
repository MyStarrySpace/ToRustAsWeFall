shader_type spatial;
// Materialize-in (portal/teleport) dissolve. As `dissolve` rises 0 -> 1 the body forms out of a
// world-space noise field, with a bright energy edge riding the forming boundary. Lit like the base
// mesh, so at dissolve = 1 it reads as the normal character (the edge glow fades out as it completes).
render_mode cull_disabled;

uniform vec4 albedo : source_color = vec4(0.7, 0.6, 0.45, 1.0);
uniform float emission_energy = 0.3;
uniform float dissolve : hint_range(0.0, 1.1) = 0.0;          // 0 = unformed (invisible), 1 = fully formed
uniform vec4 edge_color : source_color = vec4(0.36, 0.91, 0.5, 1.0);  // the forming-edge energy (terminal green)
uniform float edge_width = 0.16;
uniform float edge_energy = 5.0;
uniform float noise_scale = 6.0;
uniform sampler2D noise_tex : repeat_enable, filter_linear;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Two world-space projections so the dissolve grain reads over the whole capsule, not a flat band.
	float n = texture(noise_tex, v_world.xz * noise_scale * 0.1).r * 0.5
		+ texture(noise_tex, v_world.xy * noise_scale * 0.13).r * 0.5;
	if (n > dissolve) {
		discard;  // not formed here yet
	}
	ALBEDO = albedo.rgb;
	EMISSION = albedo.rgb * emission_energy;
	// Bright edge where the surface is only just formed (noise near the cutoff); fade the edge out as
	// the body completes so the finished character carries no leftover glow.
	float edge = smoothstep(dissolve - edge_width, dissolve, n);
	float edge_fade = 1.0 - smoothstep(0.85, 1.0, dissolve);
	EMISSION += edge_color.rgb * edge * edge_energy * edge_fade;
}
