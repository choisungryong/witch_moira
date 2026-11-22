shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;
// D24 7.4 Judgment Bolt: one pooled mesh per bolt (trunk, side branches and the forks between bodies), built once when the bolt
// is struck. Vertex colour carries the strength of each ribbon (a wide cool glow, a thin white core); fade is the bolt's life.
uniform float fade = 1.0;
void fragment(){
 ALBEDO=COLOR.rgb*fade;
 ALPHA=clamp(COLOR.a*fade,0.,1.);
}
