shader_type canvas_item;
// The skill name's fill on the descent's band (A11 12.2 as changed by U-101: an inscription cut into metal, not a brush stroke).
// The glyphs stay upright. The colour runs from `top` (bright brass) to `bottom` (old gold) down the letters, the inner edge along the TOP of every
// stroke is shaded (the stroke is cut in: shadow above, light below), and the bottom edge is lifted a little. Used on one node that draws only the fill;
// the part draws the plate, the light and the dark edge behind it.

uniform vec4 top : source_color = vec4(1.0, 0.82, 0.48, 1.0);
uniform vec4 bottom : source_color = vec4(0.67, 0.55, 0.35, 1.0);
uniform float pivot_y = 0.0;      // the name's middle, in the node's drawing space
uniform float height = 84.0;
varying float vy;

void vertex() {
	vy = VERTEX.y;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float above = texture(TEXTURE, UV + vec2(0.0, -2.5) * TEXTURE_PIXEL_SIZE).a;
	float below = texture(TEXTURE, UV + vec2(0.0, 2.5) * TEXTURE_PIXEL_SIZE).a;
	float k = smoothstep(pivot_y - height * 0.45, pivot_y + height * 0.5, vy);
	vec3 col = mix(top.rgb, bottom.rgb, k);
	col *= 1.0 - 0.55 * clamp(c.a - above, 0.0, 1.0);
	col += 0.22 * clamp(c.a - below, 0.0, 1.0);
	COLOR = vec4(col, c.a);
}
