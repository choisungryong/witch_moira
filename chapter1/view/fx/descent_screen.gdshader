shader_type canvas_item;
render_mode blend_mix;
// The descent's whole-screen layer (D15 A, D14 4.4). ONE full-rect control, ordinary alpha blending only: no additive full-screen
// area. Four things share it, never at the same time except the edge aura, which is a thin edge ring:
//   aura   the gauge is full: the element colour at the very edge of the screen
//   cut-in dark scrim, a slit in the element colour that tears open across the screen, the demon's bust slides in, one flash
//   freeze (frost sweep) crystal rim that closes in, then shatters cell by cell
//   pulse  a short tint wash for a bolt round or a break
// Colours are the element's tint only; never the enemy-telegraph crimson. No manga speed lines.

uniform vec4 tint : source_color = vec4(1.0, 0.58, 0.24, 1.0);
uniform float aspect = 1.7778;
uniform float time = 0.0;
uniform float aura = 0.0;          // 0..1 how present the edge aura is
uniform float aura_pulse = 0.0;    // 0..1 the one-time swell when the gauge fills
uniform float scrim = 0.0;         // 0..1 darkness of the cut-in
uniform float rift = 0.0;          // 0..1 how far the slit has opened (1 = the full bust band)
uniform float slide = 0.0;         // 0..1 the bust coming in (1 = settled)
uniform float retract = 0.0;       // 0..1 the picture leaving
uniform float flash = 0.0;         // 0..1 the single flash of the gesture
uniform vec2 slide_dir = vec2(1.0, 0.0);
uniform float has_art : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D art : source_color, filter_linear;
uniform float art_focus_y = 0.42;  // the part of the picture's height that sits at the band centre
uniform float freeze = 0.0;        // 0..1 the crystal rim
uniform float shatter = 0.0;       // 0..1 the rim breaking away
uniform float pulse = 0.0;         // 0..1 a tint wash
uniform float element_id = 0.0;    // 0 ember, 1 frost, 2 arc (the stand-in silhouette)
// ---- D24 sweep layers (the same one control; ordinary alpha, no additive full-screen area) ----
uniform float sky = 0.0;           // 0..1 the sky band at the top 42 % (ember: cracked red-brown cloud, frost: storm cloud, arc: thunder cloud)
uniform float sky_flash = 0.0;     // 0..1 the cloud lit from inside (arc, one per bolt, smoothed so it never strobes)
uniform float storm = 0.0;         // 0..1 frost: the ice storm sweeping in from the upper right
uniform float gust = 0.0;          // 0..1 frost: a pulse makes the wind surge
uniform vec2 storm_dir = vec2(-0.62, 0.78);   // where the wind runs to on the screen (uv, y down)
uniform float low = 0.0;           // 1 = the low-spec look: one streak layer, no cloud noise detail
uniform float fire_cover = 0.0;    // 0..1 ember finale: the flame creeping in from the edges
uniform float fire_alpha = 0.0;    // 0..1 its visibility
uniform float whiteout = 0.0;      // 0..1 one white flash (frost break, arc finale); flash_scale is applied by the host
uniform float demon = 0.0;         // 0..1 the demon in the sky layer
uniform float demon_pose = 0.0;    // 0..1 the arm swung down / the fist closed
uniform float demon_x = 0.7;       // where it stands (uv x)
uniform float has_sky_art : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D sky_art : source_color, filter_linear;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
	float n = hash21(p);
	return vec2(n, hash21(p + n + 17.0));
}

// Voronoi: x = distance to the nearest point, y = distance to the nearest edge, zw = cell id.
vec4 voronoi(vec2 p) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float d1 = 8.0;
	vec2 id1 = vec2(0.0);
	vec2 r1 = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash22(ip + g);
			vec2 r = g + o - fp;
			float d = dot(r, r);
			if (d < d1) { d1 = d; id1 = ip + g; r1 = r; }
		}
	}
	float edge = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash22(ip + g);
			vec2 r = g + o - fp;
			if (dot(r - r1, r - r1) > 0.0001) {
				edge = min(edge, dot(0.5 * (r1 + r), normalize(r - r1)));
			}
		}
	}
	return vec4(sqrt(d1), edge, id1);
}

float ell(vec2 p, vec2 c, vec2 r, float rot) {
	vec2 q = p - c;
	float cs = cos(rot);
	float sn = sin(rot);
	q = vec2(cs * q.x + sn * q.y, -sn * q.x + cs * q.y);
	return (length(q / r) - 1.0) * min(r.x, r.y);
}

// a better scrambled hash for the smooth noise (hash21's neighbouring cells are correlated and showed as blocks in the flame)
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + 11.7;
		a *= 0.5;
	}
	return s;
}

// The stand-in bust while the art slot is planned (code-drawn; only the eyes and the fingertip carry colour).
// g (0..1) swings the arm down: ember draws the hand down, frost closes the fist, arc touches two fingers to the hand.
vec4 silhouette_g(vec2 p, float elem, float g) {
	float head = ell(p, vec2(0.0, 0.07), vec2(0.082, 0.108), 0.0);
	float jaw = ell(p, vec2(0.0, 0.0), vec2(0.066, 0.085), 0.0);
	float neck = ell(p, vec2(0.0, -0.08), vec2(0.04, 0.07), 0.0);
	float shoulders = ell(p, vec2(0.0, -0.31), vec2(0.34, 0.2), 0.0);
	float hair = ell(p, vec2(0.02, 0.1), vec2(0.115, 0.14), 0.0);
	float horn_l = ell(p, vec2(-0.1, 0.2), vec2(0.016, 0.085), 0.55);
	float horn_r = ell(p, vec2(0.1, 0.2), vec2(0.016, 0.085), -0.55);
	vec2 hand_c = mix(vec2(-0.30, 0.02), vec2(-0.28, -0.16), g);
	vec2 sh_c = vec2(-0.16, -0.18);
	vec2 arm_c = (sh_c + hand_c) * 0.5;
	vec2 dv = hand_c - sh_c;
	float arm_rot = -atan(dv.x, dv.y);
	float arm = ell(p, arm_c, vec2(0.07, max(0.05, length(dv) * 0.55)), arm_rot);
	float hand = ell(p, hand_c, vec2(0.04 + 0.02 * g * step(0.5, elem) * step(elem, 1.5), 0.065), -0.2);
	if (elem > 1.5) {
		// the lightning demon holds two fingers to the back of a hand: no raised arm
		arm = ell(p, vec2(-0.12, -0.2), vec2(0.17, 0.05), 0.5);
		hand = ell(p, vec2(-0.2, -0.17 + 0.03 * g), vec2(0.04, 0.03), 0.4);
	}
	float d = min(min(min(head, jaw), min(neck, shoulders)), min(min(hair, horn_l), min(horn_r, min(arm, hand))));
	float body = 1.0 - smoothstep(-0.004, 0.004, d);
	float rim = (1.0 - smoothstep(0.0, 0.02, d)) * (1.0 - body);
	vec3 col = vec3(0.012, 0.012, 0.016);
	float eye_l = 1.0 - smoothstep(0.0, 0.006, ell(p, vec2(-0.034, 0.085), vec2(0.022, 0.0065), 0.12));
	float eye_r = 1.0 - smoothstep(0.0, 0.006, ell(p, vec2(0.034, 0.085), vec2(0.022, 0.0065), -0.12));
	float tip = 1.0 - smoothstep(0.0, 0.01, length(p - (elem > 1.5 ? vec2(-0.185, -0.15) : hand_c + vec2(-0.03, 0.055))) - 0.008 - 0.01 * g);
	float lit = max(max(eye_l, eye_r), tip) * body;
	vec3 lit_col = col + tint.rgb * (lit * 1.6);
	vec3 rgb = mix(tint.rgb * 0.5, lit_col, body);
	return vec4(rgb, max(body, rim * 0.7));
}

vec4 silhouette(vec2 p, float elem) {
	return silhouette_g(p, elem, 0.0);
}

void fragment() {
	vec2 uv = UV;
	vec2 sc = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);   // centred, in screen heights
	float edge_d = min(min(uv.x * aspect, (1.0 - uv.x) * aspect), min(uv.y, 1.0 - uv.y));
	vec4 out_c = vec4(0.0);

	// ---- aura: the gauge is full ----
	if (aura > 0.001 || aura_pulse > 0.001) {
		float reach = 0.10 + 0.10 * aura_pulse;
		float e = pow(1.0 - smoothstep(0.0, reach, edge_d), 2.0);
		float flicker = 0.78 + 0.22 * sin(time * 3.1 + uv.y * 9.0 + uv.x * 5.0);
		float a = e * flicker * (aura * 0.20 + aura_pulse * 0.30);
		out_c = vec4(tint.rgb, a);
	}

	// ---- freeze rim ----
	if (freeze > 0.001) {
		float close_in = 0.07 + 0.28 * freeze;
		vec4 v = voronoi(vec2(sc.x, sc.y) * 7.0 + 3.0);
		float crack = 1.0 - smoothstep(0.0, 0.05, v.y);
		float rimmask = 1.0 - smoothstep(close_in * 0.35, close_in, edge_d + (v.x - 0.5) * 0.04);
		float cell_h = hash21(v.zw);
		float alive = step(shatter * 1.15, cell_h + 0.001) ;
		float a = (rimmask * (0.30 + 0.40 * (0.5 + 0.5 * cell_h)) + crack * rimmask * 0.35) * alive;
		a += 0.07 * freeze * alive;
		vec3 c = mix(tint.rgb, vec3(0.92, 0.98, 1.0), 0.35 + 0.4 * crack);
		float fa = clamp(a, 0.0, 0.62) * (1.0 - shatter * 0.4);
		out_c = vec4(mix(out_c.rgb, c, fa / max(0.001, fa + out_c.a)), clamp(out_c.a + fa * (1.0 - out_c.a), 0.0, 1.0));
	}

	// ---- cut-in ----
	if (scrim > 0.001) {
		float vig = smoothstep(0.2, 1.0, length(sc * vec2(0.8, 1.2)));
		float dark = clamp(scrim * (0.74 + 0.16 * vig), 0.0, 0.92);
		out_c = vec4(vec3(0.0), max(out_c.a, dark));
		float hb = 0.36 * rift * (1.0 - retract);
		float band = 1.0 - smoothstep(hb - 0.004, hb + 0.002, abs(sc.y));
		// the slit: a thin line of the element colour before the band opens
		float slit_w = mix(0.0045, 0.0009, smoothstep(0.0, 0.2, rift));
		float slit = (1.0 - smoothstep(slit_w * 0.4, slit_w, abs(sc.y))) * smoothstep(0.0, 0.08, rift) * (1.0 - smoothstep(0.35, 1.0, rift)) * (1.0 - retract);
		float tear = smoothstep(0.0, 1.0, clamp(rift * 6.0 - abs(sc.x) / (aspect * 0.5), 0.0, 1.0));
		slit *= max(tear, 0.0);
		out_c.rgb = mix(out_c.rgb, tint.rgb * 1.2, slit);
		out_c.a = max(out_c.a, slit);
		if (rift > 0.2 && band > 0.0) {
			float s_e = 1.0 - pow(1.0 - slide, 3.0);
			vec2 off = slide_dir * (1.0 - s_e) * 0.16;
			// the ground of the band: near black with a glow of the element colour behind the head
			float glow = exp(-dot(sc - vec2(0.12, 0.05), sc - vec2(0.12, 0.05)) * 6.0);
			vec3 bg = vec3(0.015, 0.015, 0.02) + tint.rgb * glow * 0.20;
			vec3 col = bg;
			float cov = 1.0;
			float scale = mix(1.06, 1.0, s_e);
			if (has_art > 0.5) {
				vec2 auv = vec2(0.5 + (sc.x - off.x) / (aspect * scale), art_focus_y + (sc.y - off.y) / (aspect / 1.5 * scale));
				if (auv.x >= 0.0 && auv.x <= 1.0 && auv.y >= 0.0 && auv.y <= 1.0) {
					vec4 t = texture(art, auv);
					col = mix(bg, t.rgb * 0.94, s_e);
				}
			} else {
				// the stand-in is drawn y up and the screen's y runs down: flip it (it hung upside down before D24)
				vec2 sp = (sc - off) - vec2(0.12, 0.0);
				vec4 sil = silhouette(vec2(sp.x, -sp.y), element_id);
				col = mix(bg, sil.rgb, sil.a * s_e);
				col += tint.rgb * 0.0;
			}
			// the band's edges stay dark so the picture reads as lit from the slit
			float edge_fade = smoothstep(hb, hb - 0.05, abs(sc.y)) * (0.35 + 0.65 * smoothstep(0.0, 0.30, aspect * 0.5 - abs(sc.x)));
			col *= mix(0.55, 1.0, edge_fade);
			float line = (1.0 - smoothstep(0.0, 0.006, abs(abs(sc.y) - hb))) * 0.9;
			col = mix(col, tint.rgb * 1.15, line * band);
			out_c.rgb = mix(out_c.rgb, col, band * (1.0 - retract * 0.5));
			out_c.a = max(out_c.a, band);
		}
		if (flash > 0.001) {
			// bright near-white of the element colour; weight is the flash itself, so it reads as light, not as a brown wash
			vec3 fc = mix(tint.rgb, vec3(1.0), 0.8);
			out_c = vec4(mix(out_c.rgb, fc, flash * 0.7), max(out_c.a, flash * 0.9));
		}
	}

	// ---- a tint wash ----
	if (pulse > 0.001) {
		vec3 pc = mix(tint.rgb, vec3(1.0), 0.6);
		float pa = pulse * 0.34 * (0.5 + 0.5 * smoothstep(0.0, 0.6, length(sc)));
		out_c = vec4(mix(out_c.rgb, pc, pa / max(0.001, pa + out_c.a)), clamp(out_c.a + pa * (1.0 - out_c.a), 0.0, 1.0));
	}
	// ---- D24 sky band: the cloud ceiling the demon works in ----
	if (sky > 0.001) {
		float m = 1.0 - smoothstep(0.0, 0.42, uv.y);
		vec2 cp = vec2(sc.x * 1.5 + time * 0.04, uv.y * 3.2 - time * 0.015);
		float cl = low > 0.5 ? vnoise(cp * 2.0) : fbm(cp * 2.0);
		vec3 sc3;
		float sa;
		if (element_id < 0.5) {
			sc3 = mix(vec3(0.15, 0.04, 0.02), vec3(0.50, 0.15, 0.05), cl);
			float cr = 1.0 - smoothstep(0.0, 0.035, abs(vnoise(cp * 5.0 + 7.0) - 0.5));
			sc3 = mix(sc3, vec3(1.0, 0.55, 0.16), cr * (0.55 + 0.45 * sin(time * 2.5 + cl * 8.0)) * smoothstep(0.1, 0.9, m));
			sa = m * sky * (0.30 + 0.28 * cl);
		} else if (element_id < 1.5) {
			sc3 = mix(vec3(0.09, 0.16, 0.23), vec3(0.50, 0.70, 0.82), cl);
			sa = m * sky * (0.26 + 0.28 * cl);
		} else {
			sc3 = mix(vec3(0.03, 0.04, 0.08), vec3(0.20, 0.24, 0.42), cl) + vec3(0.62, 0.72, 1.0) * sky_flash * (0.4 + cl);
			sa = m * sky * (0.46 + 0.16 * cl) + sky_flash * m * 0.18;
		}
		sa = clamp(sa, 0.0, 0.58);
		float oa = out_c.a;
		out_c.rgb = mix(out_c.rgb, sc3, sa / max(0.001, sa + oa));
		out_c.a = clamp(oa + sa * (1.0 - oa), 0.0, 1.0);
	}

	// ---- D24 frost: the ice storm (two layers of slanted streaks, a drifting snow veil, a cold wash) ----
	if (storm > 0.001) {
		// A blizzard, not a floor pattern: three depths of flakes streaking one way (near ones big and fast, far ones small and slow),
		// the wind's direction swaying with slow gust bands, frost creeping in from the rim. Each pulse (gust) makes it surge.
		vec2 sdir = normalize(storm_dir);
		float dcorner = length((uv - vec2(1.0, 0.0)) * vec2(aspect, 1.0)) / (aspect + 1.0);
		float cov = clamp((storm * 1.45 - dcorner) * 3.5, 0.0, 1.0);
		float sp = 1.0 + gust * 1.6;
		vec2 bp = vec2(dot(sc, sdir) * 1.1 - time * 1.5 * sp, dot(sc, vec2(-sdir.y, sdir.x)) * 1.3);
		float band = low > 0.5 ? 0.5 : vnoise(bp) * 0.65 + vnoise(bp * 2.1 + 5.0) * 0.35;      // two octaves: cheap (the storm covers the whole screen)
		float streak = 0.0;
		for (int ly = 0; ly < 3; ly++) {
			if (low > 0.5 && ly != 1) continue;
			float cells = ly == 0 ? 8.0 : (ly == 1 ? 20.0 : 46.0);
			float speed = ly == 0 ? 3.4 : (ly == 1 ? 2.1 : 1.2);
			float len = ly == 0 ? 0.34 : (ly == 1 ? 0.22 : 0.12);
			float amp = ly == 0 ? 0.62 : (ly == 1 ? 0.45 : 0.30);
			float sway = sin(dot(sc, vec2(1.3, 0.9)) * 1.7 + time * 0.9 + float(ly) * 2.0) * 0.20 + (band - 0.5) * 0.7;
			vec2 d = vec2(sdir.x * cos(sway) - sdir.y * sin(sway), sdir.x * sin(sway) + sdir.y * cos(sway));
			float along = dot(sc, d);
			float across = dot(sc, vec2(-d.y, d.x));
			float cid = floor(across * cells);
			float h = hash21(vec2(cid, float(ly) * 13.0 + 3.0));
			float lane = 1.0 - smoothstep(0.0, ly == 0 ? 0.75 : 0.55, abs(fract(across * cells) - 0.5) * 2.0);
			float pos = fract(along * 0.22 - time * speed * (0.7 + h * 0.8) * sp + h * 7.0);
			float s1 = smoothstep(0.0, 0.02, pos) * (1.0 - smoothstep(0.02, len, pos));
			streak = max(streak, s1 * lane * step(0.42, h) * amp);
		}
		float swirl = low > 0.5 ? 0.0 : smoothstep(0.46, 0.82, band) * 0.20;
		float rim = 1.0 - smoothstep(0.0, 0.34, edge_d);
		float wa = clamp(cov * ((streak + swirl) * (1.0 + gust * 0.9) + 0.06 + 0.24 * rim), 0.0, 0.62);
		vec3 wc = mix(vec3(0.60, 0.82, 0.96), vec3(0.97, 0.99, 1.0), clamp(streak * 2.6, 0.0, 1.0));
		float oa2 = out_c.a;
		out_c.rgb = mix(out_c.rgb, wc, wa / max(0.001, wa + oa2));
		out_c.a = clamp(oa2 + wa * (1.0 - oa2), 0.0, 1.0);
	}

	// ---- D24 ember finale: flame creeping in from the edges, thin over the middle ----
	if (fire_alpha > 0.001) {
		// Flames rising from the bottom edge and licking in from the sides (value noise scrolled upward, smooth: no cells show), embers lifting off.
		float t_up = time * 3.2;
		float n1 = fbm(vec2(sc.x * 4.0, sc.y * 2.2 + t_up));
		float n2 = fbm(vec2(sc.x * 9.0 + 3.0, sc.y * 4.5 + t_up * 1.7));
		float below = 1.0 - uv.y;                                        // distance up from the bottom edge, in screen heights
		float side = min(uv.x * aspect, (1.0 - uv.x) * aspect);          // distance in from the nearest side
		float reach_b = fire_cover * (0.20 + 0.30 * n1);
		float reach_s = fire_cover * (0.10 + 0.22 * n1);
		float flame_b = 1.0 - smoothstep(reach_b * 0.35, max(reach_b, 0.001), below + (n2 - 0.5) * 0.10);
		float flame_s = 1.0 - smoothstep(reach_s * 0.35, max(reach_s, 0.001), side + (n2 - 0.5) * 0.08);
		float top = 1.0 - smoothstep(0.0, fire_cover * 0.12, uv.y + (n2 - 0.5) * 0.05);
		float flame = clamp(max(max(flame_b, flame_s), top * 0.7), 0.0, 1.0);
		float core = smoothstep(0.55, 1.0, flame) * smoothstep(0.30, 0.8, n2);
		vec3 fc2 = mix(vec3(0.70, 0.13, 0.02), vec3(1.0, 0.55, 0.12), smoothstep(0.1, 0.8, flame));
		fc2 = mix(fc2, vec3(1.0, 0.86, 0.45), core);
		// embers
		vec2 eg = vec2(sc.x * 26.0, sc.y * 15.0 + time * 5.0);
		vec2 ei = floor(eg);
		vec2 ef = fract(eg) - 0.5;
		float eh = hash21(ei);
		float ember = step(0.88, eh) * (1.0 - smoothstep(0.05, 0.16, length(ef - (hash22(ei + 3.0) - 0.5) * 0.5))) * smoothstep(0.0, 0.3, fire_cover);
		float fa = flame * (0.34 + 0.40 * smoothstep(0.2, 0.9, n1)) * fire_alpha;
		fa = max(fa, ember * 0.8 * fire_alpha);
		fc2 = mix(fc2, vec3(1.0, 0.8, 0.4), ember);
		float oa3 = out_c.a;
		out_c.rgb = mix(out_c.rgb, fc2, fa / max(0.001, fa + oa3));
		out_c.a = clamp(oa3 + fa * (1.0 - oa3), 0.0, 1.0);
	}

	// ---- D24 the demon in the sky layer (35-50 % opacity, inside the top 40 % of the screen) ----
	if (demon > 0.001) {
		vec2 dp = vec2((uv.x - demon_x) * aspect, uv.y - 0.19);
		vec2 q = vec2(dp.x, -dp.y) / 0.50;               // the stand-in is drawn y up
		float da = 0.0;
		vec3 dc = vec3(0.0);
		if (has_sky_art > 0.5) {
			// a full-length figure on a near-black ground (the grace screen's demon): its upper body, the ground turned into transparency by brightness,
			// lit from behind in the element colour; the gesture tilts it a little, pulses its light and puts a glow at the beckoning hand
			float tilt = (demon_pose - 0.35) * 0.10;
			vec2 rp = vec2(dp.x, uv.y - 0.20);
			rp = vec2(rp.x * cos(tilt) - rp.y * sin(tilt), rp.x * sin(tilt) + rp.y * cos(tilt));
			vec2 auv = vec2(0.5 + rp.x / 0.56, (rp.y + 0.20) / 0.42 * 0.5);
			if (auv.x >= 0.0 && auv.x <= 1.0 && auv.y >= 0.0 && auv.y <= 1.0) {
				vec3 t = texture(sky_art, auv).rgb;
				float lum = max(t.r, max(t.g, t.b));
				da = smoothstep(0.07, 0.30, lum);
				dc = t * (1.0 + 0.6 * demon_pose) + tint.rgb * 0.18 * (1.0 + demon_pose);
				float hand = exp(-dot(auv - vec2(0.12, 0.2), auv - vec2(0.12, 0.2)) * 60.0) * demon_pose;
				dc += tint.rgb * hand * 1.5;
				da = max(da, hand * 0.6);
			}
			float halo = exp(-dot(dp, dp) * 9.0) * 0.18;
			if (da < halo) { da = halo; dc = tint.rgb; }
		} else {
			vec4 sil = silhouette_g(q, element_id, demon_pose);
			dc = sil.rgb;
			da = sil.a;
		}
		float fade_top = smoothstep(-0.02, 0.10, uv.y) * (1.0 - smoothstep(0.34, 0.42, uv.y));
		float dalpha = da * demon * (has_sky_art > 0.5 ? 0.48 : 0.40) * fade_top;
		float oa4 = out_c.a;
		out_c.rgb = mix(out_c.rgb, dc, dalpha / max(0.001, dalpha + oa4));
		out_c.a = clamp(oa4 + dalpha * (1.0 - oa4), 0.0, 1.0);
	}

	// ---- D24 one white flash ----
	if (whiteout > 0.001) {
		out_c = vec4(mix(out_c.rgb, vec3(0.96, 0.98, 1.0), whiteout), max(out_c.a, whiteout));
	}
	COLOR = out_c;
}
