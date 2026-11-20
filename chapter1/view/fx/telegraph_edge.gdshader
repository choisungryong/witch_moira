shader_type spatial;
// A6-5 edge pass: one calm crimson line (THREAT, values in telegraph_common.gdshaderinc) with a dark halo outside it, so it reads on dark and on bright floor.
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
	float aa = 0.012;
	float bw = TELE_LINE_HALF * wt;
	float ae = clamp(0.50 + 0.22 * smoothstep(0.0, 0.7, p) + 0.28 * flash, 0.0, 0.95);
	float hot = 0.0;
	float dark = 0.0;
	float front = tele_front(kind, p, h, r);
	if (kind > 1.5 && kind < 2.5) {
		float reveal = (1.0 - smoothstep(front - 0.02, front + 0.02, mm.x)) * step(-h - 0.05, mm.x);
		// the ray tapers and fades towards its far end
		float along = clamp((mm.x + h) / max(2.0 * h, 0.01), 0.0, 1.0);
		float thin = 1.0 - TELE_RAY_TAPER * along;
		float ay = abs(mm.y);
		float bwr = max(bw * thin, 0.02);
		float line = 1.0 - smoothstep(bwr - aa, bwr + aa, ay);
		float halo = 1.0 - smoothstep(bwr + 0.03, bwr + 0.06, ay);
		float tip = 1.0 - smoothstep(TELE_RAY_TIP * wt, TELE_RAY_TIP * wt + 0.03, length(mm - vec2(front, 0.0)));
		hot = max(line * reveal * ae * thin, tip * 0.7 * step(0.01, p));
		dark = halo * reveal * 0.45;
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
			hot = max(hot, (1.0 - smoothstep(0.012, 0.035, rf)) * 0.45 * live * step(d, 0.0));
			if (style > 0.5 && style < 1.5) {
				float rc = abs(length(mm) - r * (1.5 - 0.5 * p));
				hot = max(hot, (1.0 - smoothstep(0.015, 0.045, rc)) * 0.5 * (1.0 - p));
			}
		} else {
			float xf = abs(mm.x - front);
			hot = max(hot, (1.0 - smoothstep(0.012, 0.035, xf)) * 0.45 * live * step(d, -0.03));
		}
	}
	float a = hot + dark * (1.0 - hot);
	if (a < 0.004) {
		discard;
	}
	// colours are written as sRGB (the screen value) and converted, ALBEDO is linear
	vec3 line_rgb = mix(TELE_LINE_RGB, TELE_LINE_HOT_RGB, flash);
	vec3 srgb = (line_rgb * hot + TELE_HALO_RGB * dark * (1.0 - hot)) / a;
	ALBEDO = pow(srgb, vec3(2.2));
	ALPHA = a;
}
