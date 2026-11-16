shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled;
void fragment(){
 float across=abs(UV.y-.5)*2.;
 float aa=max(fwidth(across),.012);
 float core=1.-smoothstep(.04,.12+aa*.30,across);
 float sheath=pow(max(0.,1.-across),2.4)*.34;
 // Lightning-blue edge band around the bright seam (arc colour #8fa6ff / #b9caff family).
 float band=1.-smoothstep(.10,.60,across);
 float fade=clamp(COLOR.a,0.,1.);
 // COLOR.a is the existing paid link-age fade. No independent time or phase.
 // Keep continuity at every quad joint: UV.x is not an endpoint fade here.
 vec3 blue=mix(COLOR.rgb,vec3(.40,.50,1.),.65);
 vec3 glow=blue*(sheath+band*.50)*fade+vec3(.90,.94,1.)*core*1.45*fade*fade;
 ALBEDO=glow;
 EMISSION=glow*1.10;
 ALPHA=clamp((sheath+band*.50)*fade+core*fade*fade,0.,1.);
}
