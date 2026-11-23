shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
// What the descent leaves on the floor (D15 A4.2), one flat quad centred on the sweep's centre, drawn before the enemy telegraphs
// (render_priority below theirs) and with plain alpha, so nothing here brightens an enemy's warning.
//   mode 0 ember: soot and glowing cracks behind the wall of fire, a hot strip under it, fading over a few seconds
//   mode 1 frost: crystal floor that grows from the centre over the freeze, then breaks away cell by cell
// The hero stays readable: the area right under the hero is kept lighter.

uniform int mode = 0;
uniform vec4 tint : source_color = vec4(1.0, 0.58, 0.24, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.82, 0.45, 1.0);
uniform vec2 heading = vec2(0.786, -0.618);
uniform float reach = 13.0;
uniform float progress = 0.0;      // 0..1 how far the wall has gone / how far the frost has grown
uniform float shatter = 0.0;       // frost: 0..1 the floor breaking away
uniform float fade = 1.0;          // 0..1 the trace's remaining strength
uniform float time = 0.0;
uniform vec2 hero_local = vec2(0.0);
uniform float max_alpha = 0.6;
uniform float floor_dark = 0.0;     // frost (A11 5.2): a near-black blue under the frozen floor, so bodies, shells and the hero stand out on it (0 = off)
uniform vec2 rect = vec2(0.0);      // D24: when > 0 the trace is clipped to this half-size rectangle (the screen area), soft at its edge

varying vec2 lp;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
	float n = hash21(p);
	return vec2(n, hash21(p + n + 17.0));
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// x: nearest-point distance, y: edge distance, zw: cell id
vec4 voronoi(vec2 p) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float d1 = 8.0;
	vec2 id1 = vec2(0.0);
	vec2 r1 = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hash22(ip + g) - fp;
			float d = dot(r, r);
			if (d < d1) { d1 = d; id1 = ip + g; r1 = r; }
		}
	}
	float edge = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hash22(ip + g) - fp;
			if (dot(r - r1, r - r1) > 0.0001) {
				edge = min(edge, dot(0.5 * (r1 + r), normalize(r - r1)));
			}
		}
	}
	return vec4(sqrt(d1), edge, id1);
}

void vertex() {
	lp = VERTEX.xz;
}

void fragment() {
	float r = length(lp);
	float inside = 1.0 - smoothstep(reach - 1.6, reach, r);
	if (rect.x > 0.0) {
		float rd = max(abs(lp.x) - rect.x, abs(lp.y) - rect.y);
		inside = 1.0 - smoothstep(-1.2, 1.2, rd);
	}
	float hero_clear = smoothstep(1.2, 4.0, length(lp - hero_local));
	vec3 col = vec3(0.0);
	float a = 0.0;
	if (mode == 0) {
		float along = dot(lp, heading);
		float front = -reach + 2.0 * reach * progress;
		float behind = smoothstep(front + 0.2, front - 0.8, along);
		float soot_n = vnoise(lp * 0.7) * 0.6 + vnoise(lp * 2.1 + 4.0) * 0.4;
		float soot = behind * smoothstep(0.25, 0.7, soot_n);
		// glowing cracks: thin lines where a second noise crosses a level
		float cr = abs(vnoise(lp * 1.15 + 9.0) - 0.5);
		float crack = (1.0 - smoothstep(0.0, 0.035, cr)) * behind;
		float pulse = 0.7 + 0.3 * sin(time * 3.0 + vnoise(lp) * 6.0);
		float strip = exp(-pow((along - front) / 0.9, 2.0)) * step(along, front + 1.5);
		col = mix(vec3(0.03, 0.02, 0.018), tint.rgb, crack * pulse);
		col = mix(col, hot.rgb, strip);
		a = clamp(soot * 0.62 + crack * 0.38 * pulse + strip * 0.55, 0.0, 1.0);
	} else {
		float grown = smoothstep(reach * progress + 0.8, reach * progress - 0.8, r);
		vec4 v = voronoi(lp * 0.85);
		float line = 1.0 - smoothstep(0.0, 0.06, v.y);
		float cell = hash21(v.zw);
		float alive = step(shatter * 1.15, cell + 0.001);
		float ringfront = exp(-pow((r - reach * progress) / 0.7, 2.0)) * (1.0 - shatter);
		col = mix(tint.rgb * 0.55, vec3(0.93, 0.99, 1.0), line * 0.8 + ringfront * 0.5);
		a = (0.10 + 0.08 * cell + line * 0.42 + ringfront * 0.3) * grown * alive;
		if (floor_dark > 0.0) {
			// the floor goes dark, the crystal veins stay cold-bright; the hero's spot stays lighter (hero_clear below)
			float fill = floor_dark * grown * alive;
			float vein = (line * 0.17 + ringfront * 0.14) * grown * alive;
			a = fill + vein * (1.0 - fill);
			// ALBEDO is linear: these read as a near-black blue and a pale cyan on the screen
			col = mix(vec3(0.001, 0.003, 0.010), vec3(0.25, 0.55, 0.80), vein / max(a, 0.0001));
		}
	}
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, max_alpha) * inside * hero_clear * fade;
}
