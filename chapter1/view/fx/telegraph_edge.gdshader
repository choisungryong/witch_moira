shader_type spatial;
// A6-5 edge pass: one hot crimson line (THREAT) with a dark halo outside it, so it reads on dark and on bright floor.
// The remaining time is the shape: a disc fills from the middle, a bar fills from the enemy, a ray grows to its
// full length, an elite ring closes in. The line brightens once in the last ticks (A5 T3).
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled, fog_disabled;
#include "res://chapter1/view/fx/telegraph_common.gdshaderinc"

void fragment() {
	float kind = cd.x;
	float p = cd.y;
	float h = cd.z;
	float r = cd.w;
	float style = cl.r;
	float wt = cl.g;
	float flash = cl.b;
	float aa = 0.02;
	float bw = 0.035 * wt;
	float ae = clamp(0.58 + 0.25 * smoothstep(0.0, 0.6, p) + 0.2 * flash, 0.0, 0.95);
	float hot = 0.0;
	float dark = 0.0;
	float front = tele_front(kind, p, h, r);
	if (kind > 1.5 && kind < 2.5) {
		float reveal = (1.0 - smoothstep(front - 0.02, front + 0.02, mm.x)) * step(-h - 0.05, mm.x);
		float ay = abs(mm.y);
		float line = 1.0 - smoothstep(bw - aa, bw + aa, ay);
		float halo = 1.0 - smoothstep(bw + 0.04, bw + 0.08, ay);
		float tip = 1.0 - smoothstep(0.15 * wt, 0.15 * wt + 0.04, length(mm - vec2(front, 0.0)));
		hot = max(line * reveal * ae, tip * 0.95 * step(0.01, p));
		dark = halo * reveal * 0.5;
	} else {
		float d = tele_sd(mm, kind, h, r);
		float line = 1.0 - smoothstep(bw - aa, bw + aa, abs(d + bw));
		float halo = smoothstep(-0.01, 0.01, d) * (1.0 - smoothstep(0.05, 0.09, d));
		// a cross arm leaves out the stretch inside the shared middle square
		float inner = kind > 2.5 ? step(-h + r, mm.x) : 1.0;
		hot = line * ae * inner;
		dark = halo * 0.55 * inner;
		float live = step(0.02, p) * step(p, 0.97);
		if (kind < 0.5) {
			float rf = abs(length(mm) - front);
			hot = max(hot, (1.0 - smoothstep(0.015, 0.045, rf)) * 0.55 * live * step(d, 0.0));
			if (style > 0.5 && style < 1.5) {
				float rc = abs(length(mm) - r * (1.5 - 0.5 * p));
				hot = max(hot, (1.0 - smoothstep(0.02, 0.06, rc)) * 0.6 * (1.0 - p));
			}
		} else {
			float xf = abs(mm.x - front);
			hot = max(hot, (1.0 - smoothstep(0.015, 0.045, xf)) * 0.55 * live * step(d, -0.03));
		}
	}
	float a = hot + dark * (1.0 - hot);
	if (a < 0.004) {
		discard;
	}
	// colours are written as sRGB (the screen value) and converted, ALBEDO is linear
	vec3 srgb = (vec3(1.0, 0.18, 0.31) * hot + vec3(0.10, 0.01, 0.03) * dark * (1.0 - hot)) / a;
	ALBEDO = pow(srgb, vec3(2.2));
	ALPHA = a;
}
