shader_type canvas_item;
// The body of the descent's band (A11 12.2): a band of the element's colour (vertical gradient 0.30 / 0.42 / 0.22 times the colour,
// leather grain multiplied in at 0.15) with the element's pattern over it at 0.60, drifting along the band at 8 percent of its length per second.
// Drawn once on a rectangle of band_size code units (x along the band, y across it); UV 0..1 covers the rectangle. Presentation only.
// A picture in the slot ui.descent.band.<element> replaces all of this (descent_band.gd does that when the slot has a file).
// Colours come in as uniforms from palette.gd (descent_band.gd): tint = the element colour, core = tint toward ink (the pattern's bright core),
// glow = tint darkened (the soft spread round a crack).

uniform vec4 tint : source_color = vec4(1.0, 0.58, 0.24, 1.0);
uniform vec4 core : source_color = vec4(1.0, 0.85, 0.6, 1.0);
uniform vec4 glow : source_color = vec4(0.6, 0.3, 0.1, 1.0);
uniform float element_id = 0.0;   // 0 ember (lava cracks), 1 frost (hoarfrost crystals), 2 arc (storm cloud, branching bolts)
uniform float clock = 0.0;
uniform vec2 band_size = vec2(2100.0, 216.0);
uniform float pattern_strength = 0.60;
uniform float gain = 1.0;         // per element brightness trim so the three bands sit at the same level
uniform float sat = 1.0;          // per element saturation lift (the frost colour is pale)

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	return vec2(hash21(p), hash21(p + vec2(31.7, 17.3)));
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 2.03 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return s;
}

// x: distance to the nearest point, y: distance to the cell edge (second nearest minus nearest), z: the cell's random value
vec3 voro(vec2 p) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float rid = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash22(n + g);
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				rid = hash21(n + g + 7.0);
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec3(sqrt(d1), sqrt(d2) - sqrt(d1), rid);
}

void fragment() {
	vec2 p = UV * band_size;
	vec2 q = vec2(p.x - clock * band_size.x * 0.08, p.y);

	float grain = fbm(q * 0.9);
	float fine = vnoise(q * 2.6);
	float wrinkle = 1.0 - abs(2.0 * vnoise(q * vec2(0.06, 0.12)) - 1.0);
	float leather = 0.42 + 0.34 * grain + 0.10 * fine + 0.14 * pow(wrinkle, 5.0);
	float vy = UV.y;
	float grad = vy < 0.5 ? mix(0.30, 0.42, vy * 2.0) : mix(0.42, 0.22, (vy - 0.5) * 2.0);
	vec3 col = tint.rgb * grad * gain;
	col *= mix(1.0, leather * 1.9, 0.15);
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(lum), col, sat);

	float pat = 0.0;
	float spread = 0.0;
	float dark = 0.0;
	if (element_id < 0.5) {
		// Ember: cracked ground, the cracks' hot core breathing 0.6..1.0 with a period of 1.2 s, a soft spread round them.
		vec3 v = voro(q / 52.0);
		float crack = 1.0 - smoothstep(0.0, 0.11, v.y);
		spread = (1.0 - smoothstep(0.0, 0.36, v.y)) * 0.5;
		float breathe = 0.8 + 0.2 * sin(clock * 5.236 + v.z * 6.2831);
		pat = crack * breathe;
	} else if (element_id < 1.5) {
		// Frost: six-armed crystals twice the earlier size, feathered twigs, a bright spark at the arm tips.
		vec2 cell = q / 184.0;
		vec2 id = floor(cell);
		vec2 f = fract(cell) - 0.5;
		f += (hash22(id) - 0.5) * 0.25;
		float on = step(0.22, hash21(id + 3.0));
		float r = length(f);
		float a = atan(f.y, f.x) + hash21(id) * 6.2831;
		float seg = 1.0471976;
		float aa = abs(mod(a + seg * 0.5, seg) - seg * 0.5);
		float d = r * sin(aa);
		float t = r * cos(aa);
		float arm = (1.0 - smoothstep(0.0, 0.014, d)) * step(r, 0.42);
		float twig = (1.0 - smoothstep(0.0, 0.011, abs(d - 0.45 * mod(t, 0.1)))) * step(0.06, t) * step(t, 0.36);
		float tip = (1.0 - smoothstep(0.0, 0.05, length(vec2(t - 0.42, d)))) * 1.4;
		pat = on * clamp(max(arm, twig * 0.85) + tip, 0.0, 1.0);
		spread = on * (1.0 - smoothstep(0.0, 0.05, d)) * step(r, 0.42) * 0.3;
	} else {
		// Arc: a drifting storm cloud that darkens the band, and thin branching bolts inside the thicker cloud. The bolts flash at most twice a second.
		float c = fbm(q / 80.0);
		float cloud = smoothstep(0.38, 0.78, c);
		dark = cloud * 0.35;
		float ridge = abs(fbm(q / 38.0 + vec2(0.0, 3.0)) - 0.5);
		float bolt = (1.0 - smoothstep(0.0, 0.03, ridge)) * smoothstep(0.46, 0.60, c);
		float flash = pow(max(0.0, sin(clock * 12.566)), 24.0);
		pat = clamp(bolt * (0.8 + 0.5 * flash), 0.0, 1.0);
		spread = bolt * 0.25;
	}
	col *= 1.0 - dark;
	col = mix(col, glow.rgb, spread * pattern_strength);
	col = mix(col, core.rgb, clamp(pat, 0.0, 1.0) * pattern_strength);
	COLOR = vec4(col, 1.0);
}
