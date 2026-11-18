shader_type canvas_item;
render_mode blend_mix;
#include "res://chapter1/view/hud/living_portrait/rig_field.gdshaderinc"
#include "res://chapter1/view/hud/living_portrait/rig_glow.gdshaderinc"

uniform vec2 image_size = vec2(1024.0, 1536.0);

void fragment() {
	vec2 p = UV * image_size;
	vec4 col = texture(TEXTURE, (p - body_disp(p)) / image_size);
	apply_glow(col, p);
	COLOR = col;
}
