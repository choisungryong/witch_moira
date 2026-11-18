shader_type spatial;
// Vertex animation texture shader for the baked walker (skeleton outlaw).
// Same look as the StandardMaterial3D the game builds in _materials34:
//   ALPHA_DEPTH_PRE_PASS, albedo texture * tint, rim .18 / rim_tint .12, roughness / metallic of the source material.
//
// MultiMesh instance data (use_colors and use_custom_data both on):
//   transform      position (+ knockback), yaw, scale .60 + .015 * (0..3)
//   COLOR.rgb      tint in sRGB terms, exactly the Color the game would give the material's albedo_color
//                  (base (.58,.54,.46) * ice (.48,.86,1.16) or hit flash (1.3,1.2,1.05)). Converted to linear here.
//   COLOR.a        alpha (death fade * cold-corpse fade * hero-overlap fade * victory fade)
//   INSTANCE_CUSTOM.x  base row: integer part = row, fraction = blend toward the next row
//   INSTANCE_CUSTOM.y  hit row (same encoding), < 0 = none
//   INSTANCE_CUSTOM.z  hit weight (.85 * sin(pi * age)), 0 = none
//   INSTANCE_CUSTOM.w  element tint: > 0 = ice amount 0..1, < 0 = fire amount 0..1 (negated), 0 = none.
//                      Same mix and glow as chapter_actors.gd _fx_material (FX_* constants there).
// Mesh: UV2.x = texture column of the vertex, UV2.y = upper-body weight (sum of weights on the 10 HIT34 bones).
render_mode depth_prepass_alpha;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D pos_tex : filter_nearest, repeat_disable;
uniform sampler2D nrm_tex : filter_nearest, repeat_disable;
uniform vec3 pos_center = vec3(0.0);
uniform float roughness_value = 0.79;
uniform float metallic_value = 0.03;
uniform float rim_amount = 0.18;
uniform float rim_tint_amount = 0.12;

const vec3 FX_ICE_ALBEDO = vec3(0.30, 0.62, 1.0);
const vec3 FX_ICE_GLOW = vec3(0.08, 0.34, 0.95);
const vec3 FX_FIRE_ALBEDO = vec3(1.0, 0.50, 0.14);
const vec3 FX_FIRE_GLOW = vec3(1.0, 0.34, 0.04);
const float FX_FLOOR_GLOW = 0.20;

varying vec4 inst_color;
varying float inst_fx;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

void fetch_row(float row, int col, int last, out vec3 p, out vec3 n) {
	int r0 = clamp(int(floor(row)), 0, last);
	int r1 = min(r0 + 1, last);
	float f = row - floor(row);
	vec3 p0 = texelFetch(pos_tex, ivec2(col, r0), 0).xyz;
	vec3 p1 = texelFetch(pos_tex, ivec2(col, r1), 0).xyz;
	vec3 n0 = texelFetch(nrm_tex, ivec2(col, r0), 0).xyz;
	vec3 n1 = texelFetch(nrm_tex, ivec2(col, r1), 0).xyz;
	p = mix(p0, p1, f);
	n = mix(n0, n1, f) * 2.0 - 1.0;
}

void vertex() {
	int col = int(UV2.x + 0.5);
	int last = textureSize(pos_tex, 0).y - 1;
	vec3 p;
	vec3 n;
	fetch_row(INSTANCE_CUSTOM.x, col, last, p, n);
	float hit_weight = INSTANCE_CUSTOM.z * UV2.y;
	if (hit_weight > 0.0 && INSTANCE_CUSTOM.y >= 0.0) {
		vec3 hp;
		vec3 hn;
		fetch_row(INSTANCE_CUSTOM.y, col, last, hp, hn);
		p = mix(p, hp, hit_weight);
		n = mix(n, hn, hit_weight);
	}
	VERTEX = p + pos_center;
	NORMAL = normalize(n);
	inst_color = COLOR;
	inst_fx = INSTANCE_CUSTOM.w;
}

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	float ice = max(inst_fx, 0.0);
	float fire = max(-inst_fx, 0.0);
	vec3 tint = max(inst_color.rgb, vec3(0.0));
	vec3 glow = tint * FX_FLOOR_GLOW;
	tint = mix(tint, FX_ICE_ALBEDO, 0.8 * ice);
	tint = mix(tint, FX_FIRE_ALBEDO, 0.6 * fire);
	glow += FX_ICE_GLOW * ice + FX_FIRE_GLOW * fire;
	ALBEDO = a.rgb * srgb_to_linear(tint);
	EMISSION = srgb_to_linear(glow);
	ALPHA = a.a * inst_color.a;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	RIM = rim_amount;
	RIM_TINT = rim_tint_amount;
}
