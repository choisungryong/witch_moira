// A6-5: enemy telegraph quads (shared by the fill and the edge pass).
// One quad per danger shape, drawn from a MultiMesh. Everything is read from the instance:
//   INSTANCE_CUSTOM  x = kind (0 disc, 1 capsule, 2 ray corridor, 3 open arm of a cross)
//                    y = progress 0..1 (1 - remaining ticks / that enemy's windup)
//                    z = h, half of the segment length (m)   w = r, radius or half width (m)
//   COLOR            r = style (0 normal, 1 elite/boss body, 2 floor strike), g = line weight, b = last-ticks flash
// The quad is scaled to (half x, 1, half z) metres and rotated so local +x is the attack direction,
// so VERTEX.xz * scale is metres from the quad centre.
varying vec2 mm;
varying vec4 cd;
varying vec4 cl;

void vertex() {
	vec2 sc = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[2].xyz));
	mm = VERTEX.xz * sc;
	cd = INSTANCE_CUSTOM;
	cl = COLOR;
}

// Signed distance to the danger shape (negative inside), same shapes the core uses for the hit.
float tele_sd(vec2 q, float kind, float h, float r) {
	if (kind < 0.5) {
		return length(q) - r;
	}
	if (kind < 2.5) {
		return length(q - vec2(clamp(q.x, -h, h), 0.0)) - r;
	}
	// open arm: straight sides, round far end, square back (the cross arms share a square middle)
	float dd = length(q - vec2(min(q.x, h), 0.0)) - r;
	return max(dd, -(q.x + h + r));
}

// Where the fill front is: radius for a disc, x for capsules and arms, the ray tip for a ray.
float tele_front(float kind, float p, float h, float r) {
	if (kind < 0.5) {
		return r * p;
	}
	if (kind < 1.5 || kind > 2.5) {
		return -h - r + p * (2.0 * h + 2.0 * r);
	}
	return -h + p * 2.0 * h;
}

// U-56 look values (one place). Reference: the Sacrata recording measured line rgb ~(185,52,60) (S .72, V .73, hue ~0 deg),
// floor fill rgb ~(100,34,37) (V .4), 2-4 px lines, the burst brighter than the warning. Ours before: line (255,46,79), V 1.0.
// Colours are sRGB screen values; the passes convert them.
const vec3 TELE_LINE_RGB = vec3(0.80, 0.18, 0.17);     // line, calm
const vec3 TELE_LINE_HOT_RGB = vec3(0.98, 0.30, 0.24); // line in the last ticks (the only moment it gets bright)
const vec3 TELE_HALO_RGB = vec3(0.10, 0.01, 0.02);     // dark rim next to the line (reads on bright floors, and as a brightness step)
const vec3 TELE_FILL_RGB = vec3(0.30, 0.03, 0.035);    // dark crimson floor wash (alpha blended, never additive)
const float TELE_LINE_HALF = 0.028;   // m, half width of the line at weight 1.0 (was .035)
const float TELE_RAY_TAPER = 0.40;    // a ray ends this much thinner and fainter than at the enemy
const float TELE_RAY_TIP = 0.07;      // m, radius of the ray's head dot (was .15)
const float TELE_FILL_A_MIN = 0.55;   // fill strength at progress 0 as a share of the full value; it rises to 1.0 at p = 1
const float TELE_FILL_NORMAL = 0.20;  // full fill alpha, normal enemy (was .28)
const float TELE_FILL_HEAVY = 0.24;   // elite body (was .32)
const float TELE_FILL_STRIKE = 0.28;  // floor strike / boss hazard (was .36)
const float TELE_RAY_FILL = 0.085;    // faint corridor of a ranged volley (was .10)
