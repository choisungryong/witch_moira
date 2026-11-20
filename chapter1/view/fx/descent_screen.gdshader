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

// The stand-in bust while the art slot is planned (code-drawn; only the eyes and the fingertip carry colour).
vec4 silhouette(vec2 p, float elem) {
	float head = ell(p, vec2(0.0, 0.07), vec2(0.082, 0.108), 0.0);
	float jaw = ell(p, vec2(0.0, 0.0), vec2(0.066, 0.085), 0.0);
	float neck = ell(p, vec2(0.0, -0.08), vec2(0.04, 0.07), 0.0);
	float shoulders = ell(p, vec2(0.0, -0.31), vec2(0.34, 0.2), 0.0);
	float hair = ell(p, vec2(0.02, 0.1), vec2(0.115, 0.14), 0.0);
	float horn_l = ell(p, vec2(-0.1, 0.2), vec2(0.016, 0.085), 0.55);
	float horn_r = ell(p, vec2(0.1, 0.2), vec2(0.016, 0.085), -0.55);
	float arm = ell(p, vec2(-0.22, -0.12), vec2(0.07, 0.19), -0.5);
	float hand = ell(p, vec2(-0.3, 0.02), vec2(0.04, 0.065), -0.2);
	if (elem > 1.5) {
		// the lightning demon holds two fingers to the back of a hand: no raised arm
		arm = ell(p, vec2(-0.12, -0.2), vec2(0.17, 0.05), 0.5);
		hand = ell(p, vec2(-0.2, -0.17), vec2(0.04, 0.03), 0.4);
	}
	float d = min(min(min(head, jaw), min(neck, shoulders)), min(min(hair, horn_l), min(horn_r, min(arm, hand))));
	float body = 1.0 - smoothstep(-0.004, 0.004, d);
	float rim = (1.0 - smoothstep(0.0, 0.02, d)) * (1.0 - body);
	vec3 col = vec3(0.012, 0.012, 0.016);
	float eye_l = 1.0 - smoothstep(0.0, 0.006, ell(p, vec2(-0.034, 0.085), vec2(0.022, 0.0065), 0.12));
	float eye_r = 1.0 - smoothstep(0.0, 0.006, ell(p, vec2(0.034, 0.085), vec2(0.022, 0.0065), -0.12));
	float tip = 1.0 - smoothstep(0.0, 0.01, length(p - (elem > 1.5 ? vec2(-0.185, -0.15) : vec2(-0.33, 0.075))) - 0.008);
	float lit = max(max(eye_l, eye_r), tip) * body;
	vec3 lit_col = col + tint.rgb * (lit * 1.6);
	vec3 rgb = mix(tint.rgb * 0.5, lit_col, body);
	return vec4(rgb, max(body, rim * 0.7));
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
		float close_in = 0.05 + 0.20 * freeze;
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
				vec4 sil = silhouette((sc - off) - vec2(0.12, 0.0), element_id);
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
	COLOR = out_c;
}
