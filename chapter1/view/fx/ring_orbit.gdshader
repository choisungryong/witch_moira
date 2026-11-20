shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled;
// A9: what orbits on the ring spell's radius. One shader, three kinds picked by UV2.x (set per vertex by ring_spell_fx.gd):
//   0 ribbon  a soft-edged strip (tails): UV.y -1..1 across, vertex colour alpha carries the fade along the length
//   1 head    a camera-facing sprite, UV -1..1: style 0 ember = hot core + three flickering tongues,
//             1 frost = a sharp rolling shard (UV2.y = roll), 2 arc = bright orb with short rays (UV2.y = jitter)
//   2 ground  a soft light disc on the floor under a head
// ring_spell_fx.gd makes a second copy of this code with depth_test_disabled for the in-the-air layer (heads, tails, drips).
// Nothing here reaches full white: ALPHA is capped and the colour is the element colour, never mixed with gold or crimson.
uniform int style = 0;
uniform float cap : hint_range(0.0, 1.0) = .85;
uniform float band_radius = 2.2;
uniform float band_width = .5;
uniform float band_head = 0.0;
uniform float band_heads = 3.0;
varying vec2 uvp;
varying vec2 uvk;
void vertex(){ uvp = UV; uvk = UV2; }
void fragment(){
	float kind = floor(uvk.x + .5);
	float a = 0.0;
	vec3 rgb = COLOR.rgb;
	if (kind < .5) {
		float e = clamp(1.0 - uvp.y * uvp.y, 0.0, 1.0);
		a = e * e;
	} else if (kind < 1.5) {
		vec2 p = uvp;
		float d = length(p);
		if (style == 0) {
			float ang = atan(p.y, p.x);
			float tongue = .5 + .5 * sin(ang * 3.0 + TIME * 17.0 + uvk.y * 6.0);
			float halo = clamp(1.0 - d / (.62 + .38 * tongue), 0.0, 1.0);
			float core = 1.0 - smoothstep(.12, .36, d);
			a = halo * halo * .8 + core * .5;
			rgb = mix(rgb, vec3(1.0, .78, .42), core * .6);
		} else if (style == 1) {
			// p.x runs along the travel direction. A faceted crystal: a lit upper face, a dark lower face, a bright ridge between them;
			// it narrows as it rolls edge-on and the lit side swaps while it turns (no white: the colour stays the frost colour).
			float roll = cos(uvk.y);
			float w = .3 + .5 * abs(roll);
			float diamond = abs(p.x) + abs(p.y) / w;
			a = 1.0 - smoothstep(.7, .9, diamond);
			float lit = step(0.0, p.y * sign(roll + .0001));
			float facet = mix(.45, 1.0, lit);
			float ridge = 1.0 - smoothstep(.0, .08, abs(p.y));
			float tip = 1.0 - smoothstep(.5, 1.0, abs(p.x));
			a *= facet * (1.0 + ridge * .5 * tip);
		} else {
			float ray = 0.0;
			ray = max(ray, (1.0 - smoothstep(.0, .09, abs(p.y))) * (1.0 - smoothstep(.2, 1.0, abs(p.x))));
			ray = max(ray, (1.0 - smoothstep(.0, .09, abs(p.x))) * (1.0 - smoothstep(.2, 1.0, abs(p.y))));
			float orb = 1.0 - smoothstep(.18, .55, d);
			a = orb * .6 + ray * .3;
		}
		a *= 1.0 - smoothstep(.85, 1.0, d);
	} else if (kind < 2.5) {
		float d = length(uvp);
		a = 1.0 - smoothstep(.0, 1.0, d);
		a *= a;
	} else {
		// kind 3, the floor swirl band. UV = metres from the orbit centre. Never an even line: it is brightest just behind each head
		// (travel is decreasing angle, so "behind" is larger angle), nearly out opposite it, its width wobbles around the circle and
		// the pattern flows with the heads. style 0 burnt streaks cooling to dark orange, 1 frost haze, 2 thin crawling currents.
		float r = length(uvp);
		float ang = atan(uvp.y, uvp.x);
		float n = 6.28318 / max(band_heads, 1.0);
		float behind = mod(ang - band_head, n) / n;
		float bright = pow(1.0 - behind, 2.2) * .9 + .1;
		float wob = .75 + .25 * sin(ang * 5.0 - band_head * 3.0 + TIME * 1.7);
		float w = band_width * wob;
		float dist = abs(r - band_radius);
		float profile = 1.0 - smoothstep(.0, w, dist);
		float flow = .5 + .5 * sin(ang * 9.0 + (r - band_radius) * 14.0 - band_head * 9.0 + TIME * 2.0);
		if (style == 2) {
			profile = 1.0 - smoothstep(.0, w * .5, dist);
			flow = pow(flow, 6.0);
			bright = bright * .8 + .2;
			a = profile * flow * bright;
		} else {
			a = profile * profile * bright * (.35 + .65 * flow);
		}
		if (style == 0) rgb = mix(vec3(.62, .17, .05), COLOR.rgb, clamp(bright * flow * 1.4, 0.0, 1.0));
		else if (style == 1) rgb = mix(COLOR.rgb * .55, COLOR.rgb, bright);
	}
	ALBEDO = rgb;
	ALPHA = clamp(a * COLOR.a, 0.0, cap);
}
