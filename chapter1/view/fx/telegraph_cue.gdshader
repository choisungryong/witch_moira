shader_type spatial;
// U-62 body cue: a small threat-colour pulse on a NORMAL ranged / charging enemy's body (they draw no floor telegraph).
// A thin ring marks the size; the core fills from the middle as the windup runs out (INSTANCE_CUSTOM.y = progress),
// and it flashes hot in the last ticks (COLOR.r). It never touches the floor and is at most TELE_CUE_RADIUS * 2 wide.
// Billboard, always on top (no depth test), alpha blended.
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;
#include "res://chapter1/view/fx/telegraph_look.gdshaderinc"
varying vec4 cd;
varying vec4 cl;

void vertex() {
	cd = INSTANCE_CUSTOM;
	cl = COLOR;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX.xy *= cd.x;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float d = length(q);
	float p = cd.y;
	float flash = cl.r;
	float ring = 1.0 - smoothstep(0.08, 0.2, abs(d - 0.9));
	float core = (1.0 - smoothstep(p * 0.8 - 0.1, p * 0.8 + 0.05, d)) * step(0.02, p);
	float a = max(ring * 0.75, core) * TELE_CUE_ALPHA;
	a = max(a, flash * (1.0 - smoothstep(0.7, 1.0, d)));
	if (d > 1.0 || a < 0.01) {
		discard;
	}
	vec3 srgb = mix(TELE_LINE_RGB, TELE_LINE_HOT_RGB, clamp(flash + 0.4 * p, 0.0, 1.0));
	ALBEDO = pow(srgb, vec3(2.2));
	ALPHA = clamp(a, 0.0, 1.0);
}
