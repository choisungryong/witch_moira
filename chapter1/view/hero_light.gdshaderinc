// Light field around the hero, shared by the ground, grass and prop shaders.
// The hero is the centre of the light: the floor is bright near the hero and falls to a floor level
// further out. Effect lights (combat_juice's pool) lift that darkness where they reach.
// Values are written from chapter_world.gd (HERO_LIGHT_* constants) and combat_juice.gd (spell lights).
uniform vec4 hero_lit = vec4(0.0, 0.0, 3.5, 13.0);   // hero xz, inner radius, outer radius (metres)
uniform vec2 hero_lit_level = vec2(1.3, 0.6);         // brightness factor inside the inner radius / beyond the outer radius
uniform vec4 spell_lit[6];                            // xz, reach (metres), strength 0..1 (0 = unused)

float lit_field(vec2 p) {
	float f = mix(hero_lit_level.x, hero_lit_level.y, smoothstep(hero_lit.z, hero_lit.w, distance(p, hero_lit.xy)));
	for (int i = 0; i < 6; i++) {
		vec4 s = spell_lit[i];
		float k = s.w * pow(clamp(1.0 - distance(p, s.xy) / max(s.z, 0.01), 0.0, 1.0), 1.4);
		f = mix(f, max(f, 1.0), clamp(k, 0.0, 1.0));
	}
	return f;
}
