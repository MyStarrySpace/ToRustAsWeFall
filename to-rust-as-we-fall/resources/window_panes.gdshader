shader_type spatial;

// Lit window panes. The per-vertex COLOR carries each window's OWN light — the generator sets a
// different color per pane (bright / dim / off, warm or cool), so one mesh shows a whole facade of
// individually-lit windows with no per-window material. `energy` is the global multiplier.
uniform float energy = 1.8;

void fragment() {
	ALBEDO = COLOR.rgb * 0.12;
	EMISSION = COLOR.rgb * energy;
}
