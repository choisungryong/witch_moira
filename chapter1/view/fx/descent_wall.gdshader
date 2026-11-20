shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, depth_test_disabled;
// The ember descent's wall of fire (D15 A4.2). One quad that always faces the camera (the app sets its basis from the camera each
// frame): the wall's footprint runs along the ground at a right angle to the heading, which the fixed camera shows as a vertical
// line on the screen, so the wall is a tall band that crosses the screen from left to right. Local x is the way it goes (the
// flames are dragged out behind it, x < 0), local y is up on the screen.
// Ordinary alpha, not additive: the hot core is bright, the body is dark orange and soot, so an enemy's telegraph under it stays
// readable. Nothing here is crimson.

uniform vec4 core_color : source_color = vec4(1.0, 0.86, 0.55, 1.0);
uniform vec4 flame_color : source_color = vec4(1.0, 0.45, 0.10, 1.0);
uniform vec4 soot_color : source_color = vec4(0.07, 0.03, 0.02, 1.0);
uniform vec2 quad_size = vec2(7.0, 24.0);
uniform float half_len = 9.0;      // how far the wall reaches up and down the screen at this moment
uniform float gain = 1.0;          // 0..1 strength (fades in at the start, out at the end)
uniform float time = 0.0;
uniform float max_alpha = 0.82;
uniform vec2 hero_xy = vec2(100.0, 100.0);   // the hero in this quad's own plane: the wall never covers the hero

float hash(vec2 p) {
	p = fract(p * vec2(233.34, 851.73));
	p += dot(p, p + 23.45);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + 11.7;
		a *= 0.5;
	}
	return s;
}

void fragment() {
	float x = (UV.x - 0.5) * quad_size.x;
	float y = (0.5 - UV.y) * quad_size.y;
	// ends: soft at the circle's edge, a little flame above the upper end
	float ends = (1.0 - smoothstep(half_len - 1.2, half_len + 0.4, abs(y)));
	// tongues: the wall's edge is ragged, and the raggedness runs up the screen
	float n1 = fbm(vec2(x * 0.9 - time * 1.6, y * 0.55 - time * 4.0));
	float n2 = fbm(vec2(x * 2.2 - time * 2.4, y * 1.3 - time * 7.0) + 5.0);
	float back = clamp(-x, 0.0, 6.0);
	float front = clamp(x, 0.0, 2.0);
	// body: thick right behind the front, thinning to smoke and embers
	float body_len = 3.2 + 2.6 * n1;
	float body = (1.0 - smoothstep(0.0, body_len, back)) * (1.0 - smoothstep(0.0, 0.5, front));
	body *= 0.55 + 0.75 * n2;
	// core: a narrow white-hot edge that leads
	float core = exp(-pow((x + 0.15) / 0.24, 2.0)) * (0.7 + 0.5 * n2);
	float lick = smoothstep(0.55, 0.85, n1 * (1.0 - back / 6.0)) * (1.0 - smoothstep(0.0, 6.0, back)) * 0.5;
	float density = clamp(core * 1.2 + body + lick, 0.0, 1.0) * ends;
	// colour: core hot, body orange, the far tail soot
	float heat = clamp(core * 1.4 + body * 0.9 - back * 0.12, 0.0, 1.0);
	vec3 col = mix(soot_color.rgb, flame_color.rgb, smoothstep(0.05, 0.55, heat));
	col = mix(col, core_color.rgb, smoothstep(0.55, 1.0, heat));
	vec2 hd = (vec2(x, y) - hero_xy) / vec2(1.9, 3.0);
	float hero_clear = smoothstep(0.55, 1.1, length(hd));
	float alpha = clamp(density, 0.0, 1.0) * max_alpha * gain * hero_clear;
	ALBEDO = col;
	ALPHA = alpha;
}
