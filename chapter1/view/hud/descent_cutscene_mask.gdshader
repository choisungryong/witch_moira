shader_type canvas_item;
// Shows the cut-scene's video only inside the unfolding band: a strip of half-height `half_h` round the point `centre`, turned by `angle`
// (canvas units, the same numbers the band body is drawn with), so the picture opens out of the band's shape and closes back into it (A11 12.3.3).
// Presentation only. `fade` darkens the frame (the skip cuts the picture to black in 0.1 s).

uniform vec2 centre = vec2(800.0, 180.0);
uniform float angle = -0.13962634;
uniform float half_h = 108.0;
uniform float fade = 1.0;
varying vec2 canvas_pos;

void vertex() {
	canvas_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 d = canvas_pos - centre;
	float across = -sin(angle) * d.x + cos(angle) * d.y;
	float inside = 1.0 - smoothstep(half_h - 1.5, half_h, abs(across));
	vec4 c = texture(TEXTURE, UV);
	COLOR = vec4(c.rgb * fade, c.a * inside);
}
