// Edge of the walkable ground (A10 W4). Outside the walk area the ground sinks into the dark and a thin fog.
// The rectangles come from chapter_world.gd EDGE_ROWS (one table), written once at setup. Presentation only.
uniform int edge_count = 0;
uniform vec4 edge_rect[8];                       // xmin, zmin, xmax, zmax of a walkable rectangle (metres)
uniform vec4 edge_win[8];                        // x range (min, max) in which that rectangle's zone owns the dimming
uniform vec4 edge_look = vec4(0.3, 1.8, 0.38, 0.0);   // brightness left outside, metres over which it falls, fog amount
uniform vec4 edge_fog = vec4(0.06, 0.08, 0.10, 1.0);  // fog colour

// 0 on the walkable ground, rising to 1 over edge_look.y metres outside it. 0 where no table row applies (the next zone's own
// ground is not touched); near either end of a row's x window the dimming fades out over 4 m, so there is no hard seam.
float edge_shade(vec2 p) {
	float best = 1.0e9;
	float fade = 1.0;
	bool any_row = false;
	for (int i = 0; i < 8; i++) {
		if (i >= edge_count) { break; }
		if (p.x < edge_win[i].x || p.x >= edge_win[i].y) { continue; }
		any_row = true;
		vec4 r = edge_rect[i];
		vec2 q = max(max(r.xy - p, p - r.zw), vec2(0.0));
		float d = length(q);
		if (d < best) {
			best = d;
			fade = (1.0 - smoothstep(edge_win[i].y - 4.0, edge_win[i].y, p.x)) * smoothstep(edge_win[i].x, edge_win[i].x + 4.0, p.x);
		}
	}
	return any_row ? smoothstep(0.0, edge_look.y, best) * fade : 0.0;
}
