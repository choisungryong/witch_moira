shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://chapter1/view/hero_light.gdshaderinc"
#include "res://chapter1/view/edge_dim.gdshaderinc"
uniform float age=0.0;
varying vec2 world_xz;
void vertex() {
 vec3 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 float wind=sin(world.x*.61+world.z*.39+age*1.8)*.026+sin(world.x*1.2-world.z*.44+age*2.7)*.012;
 world_xz=world.xz;
 VERTEX.x+=wind*UV.y*UV.y;
 VERTEX.z+=wind*.62*UV.y*UV.y;
}
void fragment() {
 // Match the authored-light perimeter props, with darker roots and soft tips.
 // Thin physical blades lost their shape under the current low ambient light.
 float sunk=edge_shade(world_xz);
 ALBEDO=mix(COLOR.rgb*mix(.85,1.20,UV.y)*lit_field(world_xz)*mix(1.,edge_look.x,sunk),edge_fog.rgb,sunk*edge_look.z);
}
