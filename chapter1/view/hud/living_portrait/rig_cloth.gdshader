shader_type canvas_item;
render_mode blend_mix;
#include "res://chapter1/view/hud/living_portrait/rig_field.gdshaderinc"
#include "res://chapter1/view/hud/living_portrait/rig_glow.gdshaderinc"

// Hanging cloth: follows the body field (so the hem on the floor stays put), plus a sideways bend that grows toward
// the hem and lags behind. s runs 0 at y0 to 1 at y1.

uniform float amp = 10.0;
uniform float y0 = 250.0;
uniform float y1 = 1500.0;
uniform float period = 3.7;
uniform float period2 = 6.1;
uniform float lag = 0.5;
uniform float phase = 0.0;
uniform vec2 image_size = vec2(1024.0, 1536.0);

void fragment() {
	vec2 p = UV * image_size;
	float s = clamp((p.y - y0) / (y1 - y0), 0.0, 1.0);
	float bend = pow(s, 1.5);
	float tt = t - lag * s;
	float w = 0.72 * sin(6.28318 * tt / period + phase) + 0.28 * sin(6.28318 * tt / period2 + phase * 2.0 + 1.0);
	vec2 d = body_disp(p) + vec2(amp * bend * w, 0.0);
	vec4 col = texture(TEXTURE, (p - d) / image_size);
	// hem glow strengthens toward the hem (used by the fire cloth)
	apply_glow(col, p);
	COLOR = col;
}
