shader_type canvas_item;
// A figure on the descent's band whose picture has its own dark ground (the grace screen's demon, A11 3.3 stage 1).
// The ground is keyed out by brightness: pixels darker than key_lo vanish, brighter than key_hi stay. The vertex colour (set by the
// part) carries the fade at the picture's edges and the figure's own alpha. A picture with a real alpha channel needs no key (key_hi 0).

uniform float key_lo = 0.035;
uniform float key_hi = 0.14;
uniform float lift = 1.06;

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float m = max(t.r, max(t.g, t.b));
	float keyed = key_hi <= key_lo ? 1.0 : smoothstep(key_lo, key_hi, m);
	COLOR = vec4(t.rgb * lift * COLOR.rgb, t.a * keyed * COLOR.a);
}
