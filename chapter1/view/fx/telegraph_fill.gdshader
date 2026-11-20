shader_type spatial;
// A6-5 fill pass: darkens the floor towards deep crimson as the danger fills in. Alpha blend, never additive,
// so it can not turn pink on a bright floor. Stencil: where telegraphs overlap, the fill is drawn once,
// so an overlap is not darker than a single one (A5 T4).
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled, fog_disabled;
stencil_mode read, write, compare_not_equal, 1;
#include "res://chapter1/view/fx/telegraph_common.gdshaderinc"

void fragment() {
	float kind = cd.x;
	float p = cd.y;
	float h = cd.z;
	float r = cd.w;
	float style = cl.r;
	float fa = (style > 1.5 ? TELE_FILL_STRIKE : (style > 0.5 ? TELE_FILL_HEAVY : TELE_FILL_NORMAL)) * mix(TELE_FILL_A_MIN, 1.0, smoothstep(0.0, 1.0, p));
	float a = 0.0;
	float front = tele_front(kind, p, h, r);
	if (kind > 1.5 && kind < 2.5) {
		// ray: only the faint corridor the volley really covers (half width = bolt radius + hero radius)
		float inside = 1.0 - smoothstep(r - 0.03, r, abs(mm.y));
		a = TELE_RAY_FILL * inside * (1.0 - smoothstep(front - 0.05, front, mm.x)) * step(-h, mm.x);
	} else {
		float d = tele_sd(mm, kind, h, r);
		float mask = 1.0 - smoothstep(-0.03, 0.0, d);
		float along = kind < 0.5 ? 1.0 - smoothstep(front - 0.06, front, length(mm)) : 1.0 - smoothstep(front - 0.06, front, mm.x);
		a = fa * mask * along * step(0.01, p);
	}
	if (a < 0.004) {
		discard;
	}
	// colours are written as sRGB (the screen value) and converted, ALBEDO is linear
	ALBEDO = pow(TELE_FILL_RGB, vec3(2.2));
	ALPHA = a;
}
