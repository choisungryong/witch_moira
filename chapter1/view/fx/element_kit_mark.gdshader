shader_type spatial;
// A-element-kit-screen marks (element_kit_fx.gd): the shock kit's whole battle picture is lines drawn here, never a fill, never a texture.
// One MultiMesh of 2 x 2 planes per layer (floor, head). Everything is read from the instance:
//   COLOR            rgb = sRGB colour, a = strength
//   INSTANCE_CUSTOM  x = shape   y = shape parameter   z = line half width (quad units)   w = radius (quad units) or length (metres)
// shapes
//   0 tooth    three short zig-zag arcs on a floor circle (a shocked ordinary body: a conductor)
//   1 pieces   the ring over a big body, y = cap * 256 + filled; the empty pieces are the dim brass
//   2 piece    one brighter piece of that ring, y = cap * 256 + index (a new layer, a layer going out)
//   3 ring     a thin whole circle ("about to go off")
//   4 ticks    twelve short radial ticks on a floor circle (the rod's reach: ticks, not a dashed ring)
//   5 nail     a standing nail with a small diamond on top; w = half height in metres
//   6 burst    bent rays out of a point; y = rays + seed / 10
//   7 hook     a half circle with a short kink at its end (the chain went round again)
//   8 shell    a thin zig-zag circle that turns slowly (the static shell); y = phase
//   9 bolt     a kinked line along the quad (a bolt into a body; bead at the far end); y = seed, w = half length in metres
//  10 vein     the same line with fewer kinks and the bead at the near end (a layer of the ring striking its own body)
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// sRGB like the instance colours (no source_color hint: the pow() at the end is the only conversion)
uniform vec4 empty_color = vec4(0.4, 0.33, 0.26, 0.35);
const float NAIL_HALF_WIDTH_M = 0.2;

// The short half width (metres) of a bolt's quad grows with its length so a long bolt kinks wider; element_kit_fx.gd `_bolt_side` is the same formula.
float bolt_side(float half_length_m) {
	return clamp(0.2 + 0.2 * half_length_m, 0.3, 0.9);
}

varying vec4 cd;
varying vec4 cl;

void vertex() {
	cd = INSTANCE_CUSTOM;
	cl = COLOR;
}

float hash(float x) {
	return fract(sin(x * 12.9898 + 4.1414) * 43758.5453);
}

float tri(float x) {
	return abs(fract(x) * 2.0 - 1.0) * 2.0 - 1.0;
}

float line_of(float d, float half_w, float aa) {
	return 1.0 - smoothstep(half_w, half_w + aa, d);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float shape = cd.x;
	float r = length(p);
	float aa = max(fwidth(r), 0.002);
	float ang = fract(atan(p.x, -p.y) / TAU);
	float a = 0.0;
	vec3 col = cl.rgb;
	float strength = cl.a;
	if (shape < 0.5) {
		// zig-zag arcs: 3 arcs, 40% gap, 4 teeth each; the tooth leans the line off the circle by a tenth of its radius
		float seg = ang * 3.0;
		float local = fract(seg) / 0.6;
		float off = tri(local * 4.0) * cd.w * 0.11;
		float d = abs(r - cd.w - off) * 0.8;
		a = line_of(d, cd.z, aa) * step(local, 1.0);
	} else if (shape < 1.5) {
		float cap = floor(cd.y / 256.0);
		float filled = cd.y - cap * 256.0;
		float k = floor(ang * cap);
		float s = fract(ang * cap);
		float g = 9.0 / (360.0 / cap) * 0.5;
		float inside = step(g, s) * step(s, 1.0 - g);
		float line = line_of(abs(r - cd.w), cd.z, aa) * inside;
		if (k < filled) {
			a = line * 0.95;
		} else {
			a = line * empty_color.a;
			col = empty_color.rgb;
		}
	} else if (shape < 2.5) {
		float cap = floor(cd.y / 256.0);
		float idx = cd.y - cap * 256.0;
		float k = floor(ang * cap);
		float s = fract(ang * cap);
		float g = 9.0 / (360.0 / cap) * 0.5;
		float inside = step(g, s) * step(s, 1.0 - g) * step(abs(k - idx), 0.5);
		a = line_of(abs(r - cd.w), cd.z * 1.6, aa) * inside;
	} else if (shape < 3.5) {
		a = line_of(abs(r - cd.w), cd.z, aa);
	} else if (shape < 4.5) {
		// ticks: cd.z is the tick's half length in quad units, its width a fifth of that
		float across = abs(fract(ang * 12.0 + 0.5) - 0.5) / 12.0 * TAU * r;
		// the twelve ticks, and the hair line of the circle they sit on (so they read as one dial, not as scattered dashes)
		a = max(step(across, cd.z * 0.22) * step(abs(r - cd.w), cd.z), line_of(abs(r - cd.w), aa * 0.8, aa) * 0.3);
	} else if (shape < 5.5) {
		float h = cd.w;
		vec2 m = vec2(p.x * NAIL_HALF_WIDTH_M, UV.y * 2.0 * h);
		// shaft from just under the diamond to a point at the foot
		float shaft_w = 0.03 * (1.0 - smoothstep(h * 1.2, h * 2.0, m.y) * 0.9);
		float shaft = step(abs(m.x), shaft_w) * step(0.16, m.y);
		float diamond = step(abs(m.x) / 0.085 + abs(m.y - 0.1) / 0.1, 1.0);
		a = max(shaft, diamond);
	} else if (shape < 6.5) {
		float n = floor(cd.y);
		float seed = fract(cd.y) * 10.0;
		float R = cd.w;
		float t01 = r / R;
		float u = fract((ang + seed * 0.37) * n);
		float k = floor((ang + seed * 0.37) * n);
		float c_in = 0.5;
		float c_out = 0.5 + (hash(k + seed * 7.0) - 0.5) * 0.8;
		float split = 0.55;
		float center = t01 < split ? c_in : c_out;
		float arc_d = abs(u - center) / n * TAU * r;
		float width = cd.z * (1.0 - t01 * 0.55);
		float ray = line_of(arc_d, width, aa) * step(0.14, t01) * step(t01, 1.0);
		// the bend: a short tangential bridge where the ray steps sideways
		float bridge_u = (u - min(c_in, c_out)) / max(abs(c_out - c_in), 0.001);
		float bridge = line_of(abs(t01 - split) * R, width, aa) * step(0.0, bridge_u) * step(bridge_u, 1.0) * step(0.001, abs(c_out - c_in));
		a = max(ray, bridge);
		// the ray is hottest at its root and white at its tip is not wanted (it would read as a flash): root only
		col = mix(col, vec3(1.0), (1.0 - smoothstep(0.1, 0.5, t01)) * 0.7);
	} else if (shape < 7.5) {
		float line = line_of(abs(r - cd.w), cd.z, aa);
		float half_lap = step(ang, 0.5);
		// the end of the hook (bottom of the half circle): a short stroke bent back inside
		vec2 s0 = vec2(0.0, cd.w);
		vec2 s1 = vec2(-cd.w * 0.45, cd.w * 0.5);
		vec2 sd = s1 - s0;
		float sh = clamp(dot(p - s0, sd) / dot(sd, sd), 0.0, 1.0);
		float stroke = line_of(length(p - s0 - sd * sh), cd.z, aa);
		a = max(line * half_lap, stroke);
	} else if (shape < 8.5) {
		float off = tri(ang * 18.0 + cd.y) * cd.w * 0.035;
		a = line_of(abs(r - cd.w - off), cd.z, aa);
	} else {
		bool vein = shape > 9.5;
		float seed = cd.y;
		float L = cd.w;
		float side = bolt_side(L);
		float segs = vein ? 3.0 : (L > 2.5 ? 7.0 : 5.0);
		float t = UV.x;
		float kf = t * segs;
		float k = floor(kf);
		float f = fract(kf);
		float amp = vein ? 0.45 : 0.6;
		float y0 = (k < 0.5) ? 0.0 : (hash(seed + k) * 2.0 - 1.0) * amp;
		float y1 = (k > segs - 1.5) ? 0.0 : (hash(seed + k + 1.0) * 2.0 - 1.0) * amp;
		float yc = mix(y0, y1, f);
		float slope = (y1 - y0) * side / max(2.0 * L / segs, 0.05);
		float dq = abs(p.y - yc) / sqrt(1.0 + slope * slope);
		float body = line_of(dq, cd.z, fwidth(p.y) + 0.002);
		float core = line_of(dq, cd.z * 0.35, fwidth(p.y) + 0.002);
		// a bead where the bolt lands (conductor) or where the layer left the ring (vein)
		float along_m = vein ? t * 2.0 * L : (1.0 - t) * 2.0 * L;
		float bead = 1.0 - smoothstep(0.07, 0.10, length(vec2(along_m, p.y * side)));
		float lit = vein ? 1.0 - t : t;
		// the colour stays ARC along the line; only the hot end and a thin core go toward white
		col = mix(cl.rgb, vec3(1.0), clamp(lit * lit * lit * 0.7 + core * 0.2 + bead * 0.6, 0.0, 1.0));
		a = max(body, bead) * (0.55 + 0.45 * lit);
	}
	a *= strength;
	if (a < 0.004) {
		discard;
	}
	ALBEDO = pow(col, vec3(2.2));
	ALPHA = clamp(a, 0.0, 1.0);
}
