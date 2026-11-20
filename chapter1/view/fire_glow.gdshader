shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
// U-57: the orange light a fireball throws on the floor. A soft radial patch, no white, peak well under .85.
void fragment(){
 vec2 p=UV*2.-1.;
 float r=length(p);
 float g=pow(1.-smoothstep(0.,1.,r),2.2);
 ALBEDO=vec3(.50,.17,.02)*g*.40;
 ALPHA=g;
}
