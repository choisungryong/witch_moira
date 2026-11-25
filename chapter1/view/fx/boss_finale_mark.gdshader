shader_type spatial;
// D-boss-finale screen marks (A-boss-finale-screen, boss_finale_fx.gd): one MultiMesh of flat 2 x 2 planes, scaled so local radius 1.0 is the
// quad's half extent. Never filled with a bright colour, never additive. Everything is read from the instance:
//   COLOR            rgb = sRGB screen colour, a = strength
//   INSTANCE_CUSTOM  x = shape (0 dashed ring, 1 soft disc, 2 ring or arc, 3 rising dust column)
//                    y = shape parameter (dashed: dash phase; ring: share of the lap drawn, clockwise from 12 o'clock, 1 = whole; column: height share)
//                    z = line half width, in quad units       w = ring or disc radius, in quad units
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

varying vec4 cd;
varying vec4 cl;

void vertex() {
	cd = INSTANCE_CUSTOM;
	cl = COLOR;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float shape = cd.x;
	float r = length(p);
	float aa = max(fwidth(r), 0.002);
	float ang = fract(atan(p.x, -p.y) / 6.2831853);
	float a = 0.0;
	if (shape < 0.5) {
		// the dashed ring of the landing spot: "not yet" (a solid ring with a fill is "soon")
		float line = 1.0 - smoothstep(cd.z, cd.z + aa, abs(r - cd.w));
		a = line * step(fract(ang * 28.0 + cd.y), 0.55);
	} else if (shape < 1.5) {
		a = 1.0 - smoothstep(cd.w * 0.5, cd.w, r);
	} else if (shape < 2.5) {
		float line = 1.0 - smoothstep(cd.z, cd.z + aa, abs(r - cd.w));
		a = line * (1.0 - smoothstep(cd.y - 0.004, cd.y + 0.004, ang));
		if (cd.y >= 0.999) {
			a = line;
		}
	} else {
		// a short dust column: wide at the foot, thin and faint at the top (UV.y 1 is the foot)
		float up = 1.0 - UV.y;
		float width = mix(0.55, 0.12, up);
		a = (1.0 - smoothstep(width * 0.5, width, abs(p.x))) * (1.0 - smoothstep(cd.y * 0.8, cd.y, up)) * (1.0 - up * 0.6);
	}
	a *= cl.a;
	if (a < 0.004) {
		discard;
	}
	ALBEDO = pow(cl.rgb, vec3(2.2));
	ALPHA = a;
}
