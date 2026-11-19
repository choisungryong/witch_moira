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
