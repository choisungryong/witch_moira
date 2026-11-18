// Element light on a layer: pixels that match a colour pattern (cyan veins, glowing cracks, violet veins) breathe in
// brightness, and a light can travel along a line (the ice arm). Geometry is never touched.

uniform float t = 0.0;
uniform float glow_amount = 0.0;
uniform vec3 g_w = vec3(-1.0, 0.0, 1.0);
uniform float g_bias = 0.0;
uniform float g_gain = 2.2;
uniform vec3 g_rgb = vec3(0.4, 0.8, 1.0);
uniform float g_mul = 0.10;
uniform float g_pulse = 0.14;
uniform float g_period = 2.5;
uniform float g_band = 0.0;
uniform vec2 g_from = vec2(640.0, 450.0);
uniform vec2 g_to = vec2(790.0, 230.0);

void apply_glow(inout vec4 col, vec2 p) {
	if (glow_amount <= 0.0) {
		return;
	}
	float mask = clamp((dot(col.rgb, g_w) - g_bias) * g_gain, 0.0, 1.0);
	float tt = 6.28318 * t / g_period;
	float pulse = 0.5 + 0.5 * (0.65 * sin(tt) + 0.35 * sin(tt * 1.73 + 1.3));
	col.rgb *= 1.0 + glow_amount * mask * (g_mul + g_pulse * pulse);
	if (g_band > 0.0) {
		vec2 dir = g_to - g_from;
		float s = dot(p - g_from, dir) / dot(dir, dir);
		float head = fract(t / 5.0);
		float band = exp(-pow((s - head * 1.5 + 0.25) * 7.0, 2.0));
		col.rgb += glow_amount * g_rgb * mask * band * g_band * col.a;
	}
}
