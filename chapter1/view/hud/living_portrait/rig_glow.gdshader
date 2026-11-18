shader_type canvas_item;
render_mode blend_mix;
#include "res://chapter1/view/hud/living_portrait/rig_glow.gdshaderinc"

// Layers that move rigidly (arms, head) and only need the element light.

uniform vec2 image_size = vec2(1024.0, 1536.0);

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	apply_glow(col, UV * image_size);
	COLOR = col;
}
