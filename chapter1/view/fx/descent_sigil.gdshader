shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// A11 5.1: the sign under the hero while the descent is called and sweeps. One flat quad, 6 m across (the rim of the outer ring is 3 m from
// the centre), plain alpha, drawn BEFORE every enemy telegraph (render_priority below theirs), floor alpha capped (max_alpha, 0.55).
//   two brass rings (0.12 m and 0.05 m wide) + a ring of 24 invented glyphs that turns + one sign in the element's colour in the middle:
//     ember: three flame tongues / frost: a six-armed crystal (arms with side branches, a hexagon: NOT a hexagram) / arc: three bent bolts
// The glyphs are made of a stem and one or two slanted strokes and a dot: they never form a cross, a pentagram or any real symbol.
// low = 1 leaves the glyph ring out. When the slot fx.descent.sigil.<element> has a picture, the picture is drawn instead (has_art).

uniform vec4 tint : source_color = vec4(1.0, 0.58, 0.24, 1.0);
uniform vec4 brass : source_color = vec4(0.667, 0.553, 0.345, 1.0);
uniform vec4 brass_dim : source_color = vec4(0.4, 0.325, 0.263, 1.0);
uniform float element_id = 0.0;     // 0 ember, 1 frost, 2 arc
uniform float draw = 1.0;           // 0..1 the circle being drawn (a sweep round the ring, starting at the top)
uniform float fade = 1.0;           // 0..1 overall strength
uniform float max_alpha = 0.55;     // floor alpha cap
uniform float spin = 0.0;           // radians, the glyph ring's turn
uniform float low = 0.0;
uniform float has_art : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D art : source_color, filter_linear;

varying vec2 lp;

const float TAU_ = 6.28318530718;

float hash11(float n) {
	return fract(sin(n * 127.1 + 11.7) * 43758.5453);
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.00001), 0.0, 1.0);
	return length(pa - ba * h);
}

float line_mask(float d, float w, float aa) {
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + aa, d);
}

mat2 rot(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

void vertex() {
	lp = (UV - vec2(0.5)) * 2.0;
}

void fragment() {
	vec2 p = lp;
	float r = length(p);
	float aa = max(fwidth(r) * 1.3, 0.0015);
	// the circle is drawn as a sweep round the ring from the top, clockwise on the floor
	float ang01 = fract(atan(p.x, -p.y) / TAU_);
	float reveal = 1.0 - smoothstep(draw * 1.06 - 0.05, draw * 1.06, ang01);
	if (has_art > 0.5) {
		vec4 t = texture(art, UV);
		ALBEDO = t.rgb;
		ALPHA = clamp(t.a * max_alpha * fade * reveal, 0.0, 1.0);
	} else {
		float a_b = 0.0;      // brass strokes
		float a_t = 0.0;      // element strokes
		// two rings: 0.12 m and 0.05 m on a 6 m disc (radius units of 3 m)
		a_b = max(a_b, line_mask(abs(r - 0.955), 0.040, aa) * 0.95);
		a_b = max(a_b, line_mask(abs(r - 0.880), 0.0167, aa) * 0.75);
		// the glyph ring between two thin lines
		if (low < 0.5) {
			a_b = max(a_b, line_mask(abs(r - 0.835), 0.007, aa) * 0.55);
			a_b = max(a_b, line_mask(abs(r - 0.615), 0.007, aa) * 0.55);
			float a = atan(p.y, p.x) + spin;
			float cell_f = a / TAU_ * 24.0;
			float cell = floor(cell_f);
			float u = (fract(cell_f) - 0.5) * (TAU_ * 0.725 / 24.0);     // along the ring, in radius units
			float v = r - 0.725;                                          // across the ring
			vec2 q = vec2(u, v);
			float h0 = hash11(mod(cell, 24.0) + 3.0);
			float h1 = hash11(mod(cell, 24.0) + 41.0);
			float h2 = hash11(mod(cell, 24.0) + 97.0);
			float len = 0.045 + 0.025 * h0;
			float g = seg(q, vec2(0.0, -len), vec2(0.0, len));
			float sgn = h2 > 0.5 ? 1.0 : -1.0;
			g = min(g, seg(q, vec2(0.0, -0.02), vec2(0.04 * sgn, 0.02 + 0.03 * h1)));
			if (h0 > 0.5) g = min(g, seg(q, vec2(0.0, 0.01 + 0.02 * h2), vec2(-0.035 * sgn, 0.045)));
			float dot_y = (h1 > 0.5 ? 1.0 : -1.0) * 0.062;
			g = min(g, length(q - vec2(0.045 * sgn * (h0 - 0.3), dot_y)) - 0.004);
			a_b = max(a_b, line_mask(g, 0.0075, aa) * 0.80);
		}
		// the element's sign
		float w = 0.012;
		if (element_id < 0.5) {
			// three flame tongues at 120 degrees, each a curled drop pointing outward
			float a3 = atan(p.y, p.x);
			float sector = floor((a3 + 1.0472) / 2.0944);
			vec2 q = rot(-(sector * 2.0944)) * p;
			float s = q.x;
			float tt = clamp((s - 0.07) / 0.44, 0.0, 1.0);
			float env = 0.105 * pow(sin(3.14159 * tt), 0.8) * (1.0 - 0.45 * tt);
			float curl = 0.07 * tt * tt;
			float dd = abs(q.y - curl) - env;
			float inside = step(0.07, s) * step(s, 0.51);
			float outline = (1.0 - smoothstep(w * 0.35, w * 0.35 + aa * 2.0, abs(dd))) * inside;
			float fill = (1.0 - smoothstep(0.0, aa * 2.0, dd)) * inside * 0.28;
			a_t = max(a_t, max(outline * 0.95, fill));
			a_t = max(a_t, line_mask(abs(r - 0.075), 0.012, aa) * 0.9);
		} else if (element_id < 1.5) {
			// a six-armed crystal: arms with two pairs of side branches, a hexagon (never the two-triangle star)
			float a6 = atan(p.y, p.x);
			float a_f = mod(a6 + 0.5236, 1.0472) - 0.5236;
			vec2 q = vec2(cos(a_f), sin(a_f)) * r;
			float d = seg(q, vec2(0.04, 0.0), vec2(0.52, 0.0));
			d = min(d, seg(q, vec2(0.22, 0.0), vec2(0.31, 0.085)));
			d = min(d, seg(q, vec2(0.22, 0.0), vec2(0.31, -0.085)));
			d = min(d, seg(q, vec2(0.37, 0.0), vec2(0.44, 0.06)));
			d = min(d, seg(q, vec2(0.37, 0.0), vec2(0.44, -0.06)));
			a_t = max(a_t, line_mask(d, w, aa) * 0.95);
			float hex = max(max(abs(dot(p, vec2(1.0, 0.0))), abs(dot(p, vec2(0.5, 0.866)))), abs(dot(p, vec2(-0.5, 0.866))));
			a_t = max(a_t, line_mask(abs(hex - 0.155), 0.010, aa) * 0.9);
			a_t = max(a_t, (1.0 - smoothstep(0.0, aa * 2.0, hex - 0.155)) * 0.16);
		} else {
			// three bent bolts at 120 degrees
			float a3 = atan(p.y, p.x);
			float sector = floor((a3 + 1.0472) / 2.0944);
			vec2 q = rot(-(sector * 2.0944)) * p;
			float d = seg(q, vec2(0.09, 0.0), vec2(0.20, 0.07));
			d = min(d, seg(q, vec2(0.20, 0.07), vec2(0.28, -0.06)));
			d = min(d, seg(q, vec2(0.28, -0.06), vec2(0.40, 0.07)));
			d = min(d, seg(q, vec2(0.40, 0.07), vec2(0.52, 0.0)));
			a_t = max(a_t, line_mask(d, w * 1.1, aa) * 0.95);
			a_t = max(a_t, line_mask(abs(r - 0.075), 0.012, aa) * 0.9);
		}
		float a_all = max(a_b, a_t);
		vec3 col = mix(brass.rgb, tint.rgb * 0.82, a_t / max(a_b + a_t, 0.0001));   // under the hero: never a white-hot sign
		ALBEDO = col;
		ALPHA = clamp(a_all * max_alpha * fade * reveal, 0.0, 1.0) * (1.0 - smoothstep(0.985, 1.0, r));
	}
}
