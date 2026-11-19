shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled;
// A6-RS RS1/RS2: the ring spell's ground layers in one flat quad at the hero's feet (one draw call, no light).
//  layer 1, the boundary ring (always on): style 0 ember = one unbroken band, 1 frost = ring with 12 inward spikes (RS2: longer and
//          brighter, they were not readable), 2 arc = two rings. Alpha base_alpha is driven by the cooldown (smooth, never on/off).
//  layer 2, the pulse (cast.shape == "ring"): a band from near_cm out to the ring edge in .08 s, gone .12 s later. Bright inside,
//          falloff_floor at the edge. Nothing inside 1 m (the hero's box).
//  dull: a 24 degree piece of the ring turns grey for .15 s where a strong enemy took the hit (RS1, V-7).
//  thick (RS2, I2 detonation): up to three 30 degree pieces of the ring swell to about 2.4x width and brighten for .24 s (it is in full strength while the .2 s pulse fades, so it is not drowned by it) ("the ring
//          got thicker for one beat"). Each slot is (angle, age); age < 0 is off.
uniform vec4 tint : source_color = vec4(1.0);
uniform float radius = 2.2;
uniform float half_size = 3.0;
uniform int style = 0;
uniform float base_alpha = .3;
uniform float pulse_age = -1.0;
uniform float pulse_near = 1.2;
uniform float pulse_floor = 1.0;
uniform float pulse_width = 1.0;
uniform float pulse_gain = .85;
uniform float dull_angle = 0.0;
uniform float dull_age = -1.0;
uniform float swell_gain = .62;
uniform vec2 thick_a = vec2(0.0, -1.0);
uniform vec2 thick_b = vec2(0.0, -1.0);
uniform vec2 thick_c = vec2(0.0, -1.0);
varying vec2 lp;
void vertex(){ lp = VERTEX.xz * half_size; }
float band(float d, float w, float px){ return 1.0 - smoothstep(w * .5 - px, w * .5 + px, abs(d)); }
float slot(vec2 s, float a){
	if (s.y < 0.0) return 0.0;
	float dd = abs(mod(a - s.x + 3.14159, 6.28318) - 3.14159);
	return (1.0 - smoothstep(.22, .30, dd)) * (1.0 - smoothstep(.07, .24, s.y));
}
void fragment(){
	float r = length(lp);
	float a = atan(lp.y, lp.x);
	float px = fwidth(r);
	float ring = 0.0;
	if (style == 0) {
		ring = band(r - radius, .08, px);
	} else if (style == 1) {
		ring = band(r - radius, .05, px);
		float sector = 6.28318 / 12.0;
		float da = abs(fract(a / sector + .5) - .5) * sector * r;
		float depth = (radius - r) / .22;
		float tooth_w = .06 * (1.0 - depth) + .008;
		float tooth = step(0.0, depth) * step(depth, 1.0) * (1.0 - smoothstep(tooth_w * .6, tooth_w, da));
		ring = max(ring, tooth * 1.7);
	} else {
		ring = max(band(r - radius, .045, px), band(r - (radius - .11), .045, px));
	}
	float pulse = 0.0;
	if (pulse_age >= 0.0) {
		float e = 1.0 - pow(1.0 - clamp(pulse_age / .08, 0.0, 1.0), 2.0);
		float outer = mix(pulse_near, radius, e);
		float inner = max(1.0, outer - .45 * pulse_width);
		float m = smoothstep(inner - .05, inner + .05, r) * (1.0 - smoothstep(outer - .05, outer + .05, r));
		float k = clamp((r - inner) / max(outer - inner, .05), 0.0, 1.0);
		float fade = (1.0 - smoothstep(.08, .20, pulse_age)) * smoothstep(0.0, .03, pulse_age + .015);
		pulse = m * mix(1.0, pulse_floor, k) * fade * pulse_gain;
	}
	float dull = 0.0;
	if (dull_age >= 0.0) {
		float dd = abs(mod(a - dull_angle + 3.14159, 6.28318) - 3.14159);
		dull = (1.0 - smoothstep(.17, .23, dd)) * (1.0 - smoothstep(0.0, .15, dull_age)) * band(r - radius, .14, px);
	}
	float thick = max(slot(thick_a, a), max(slot(thick_b, a), slot(thick_c, a)));
	float swell = thick * band(r - radius, .19, px);
	vec3 grey = vec3(.725, .698, .631);
	ALBEDO = mix(tint.rgb, grey, clamp(dull * 2.0, 0.0, 1.0));
	ALPHA = clamp(ring * base_alpha * (1.0 - dull) + pulse + dull * .5 + swell * swell_gain, 0.0, .85);
}
