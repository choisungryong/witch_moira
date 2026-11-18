shader_type canvas_item;
render_mode blend_mix;

// Entrance: a veil of darkness over the whole picture lifts from the bottom upward. p goes 0 to 1.

uniform float p = 1.0;

void fragment() {
	float edge = 1.35 - 1.6 * p;
	float a = 1.0 - smoothstep(edge - 0.4, edge + 0.05, UV.y);
	COLOR = vec4(0.01, 0.02, 0.05, a);
}
