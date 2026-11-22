shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled;
// D24 what a strike leaves: one shader, two layers (uniform layer).
//   layer 0  flat on the floor (a 2 x 2 plane; local radius 0.8 is the real radius, the host scales by radius / 0.8):
//            kind 0 ember impact: white-hot flash (first 0.08 s), a hot shock ring that opens to the radius, a ragged soot crater with
//                     cooling lava cracks that fades over its life (3 s)
//            kind 1 arc strike: a blue-white star flash, a scorch with a few thin branching burn lines (1 s)
//   layer 1  billboard (a 2 x 2 quad): kind 0 only, the fire dome that rises and turns to smoke (0.8 s)
// custom.x = age in seconds, custom.y = seed, custom.z = kind, custom.w = life in seconds.
// Plain alpha only. Never the crimson of an enemy's attack: the ring is orange-yellow and open (broken by noise).
uniform int layer = 0;
uniform vec2 hero_uv = vec2(-1.0);   // the hero on the screen (viewport uv): the dome and the flash thin out over the hero
uniform float aspect = 1.7778;
varying vec4 bd;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+1.),f.x),f.y);}
void vertex(){
 bd=INSTANCE_CUSTOM;
 if(layer==1){
  vec3 sc=vec3(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz),length(MODEL_MATRIX[2].xyz));
  VERTEX*=sc;
  MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
 }
}
void fragment(){
 float age=bd.x;
 float sd=bd.y*31.;
 float life=max(bd.w,.05);
 float kind=bd.z;
 vec3 col=vec3(0.);
 float a=0.;
 if(layer==0){
  vec2 p=UV*2.-1.;
  float r=length(p);
  float n=noise(p*3.4+sd);
  if(kind<.5){
   float edge=1.-smoothstep(.62+.12*n,.80+.04*n,r);
   float fadeout=1.-smoothstep(.55,1.,age/life);
   float grow=smoothstep(0.,.10,age);
   a=edge*.62*grow*fadeout*(.75+.25*n);
   col=vec3(.035,.022,.014);
   // lava cracks cooling down
   float cr=1.-smoothstep(0.,.05,abs(noise(p*4.+sd*2.)-.5));
   float heat=clamp(1.-age/(life*.55),0.,1.);
   col=mix(col,vec3(1.,.42,.07),cr*heat*(.6+.4*sin(TIME*6.+n*9.)));
   a=max(a,cr*heat*.75*edge*grow);
   // shock ring: open, noisy, never closed
   float rr=.80*clamp(age/.34,0.,1.);
   float ring=(1.-smoothstep(0.,.07,abs(r-rr)))*(1.-smoothstep(.20,.34,age))*smoothstep(.25,.55,noise(vec2(atan(p.y,p.x)*2.4+sd,age*3.)));
   col=mix(col,vec3(1.,.74,.28),ring);
   a=max(a,ring*.8);
   // the flash
   float fl=exp(-r*r*3.2)*(1.-smoothstep(0.,.09,age));
   col=mix(col,vec3(1.,.9,.6),fl);
   a=max(a,fl*.95);
  }else{
   float edge=1.-smoothstep(.34+.10*n,.52+.04*n,r);
   float fadeout=1.-smoothstep(.35,1.,age/life);
   a=edge*.42*fadeout*smoothstep(0.,.05,age);
   col=vec3(.03,.03,.045);
   float ang=atan(p.y,p.x);
   float spoke=1.-smoothstep(0.,.10,abs(fract(ang*1.15+sd)-.5)*2.-.0);
   float burn=spoke*(1.-smoothstep(.0,.78,r))*step(.12,r)*(1.-smoothstep(0.,.5,age/life))*(.5+.5*noise(vec2(ang*3.,sd)));
   col=mix(col,vec3(.7,.8,1.),burn);
   a=max(a,burn*.7);
   float fl=exp(-r*r*7.)*(1.-smoothstep(0.,.12,age));
   float star=max(0.,1.-abs(p.x)*9.)*max(0.,1.-abs(p.y)*1.1)+max(0.,1.-abs(p.y)*9.)*max(0.,1.-abs(p.x)*1.1);
   col=mix(col,vec3(.92,.95,1.),clamp(fl+star*.5*(1.-smoothstep(0.,.1,age)),0.,1.));
   a=max(a,clamp(fl+star*.4*(1.-smoothstep(0.,.1,age)),0.,1.)*.95);
  }
 }else{
  // fire dome rising and going to smoke
  float t=clamp(age/life,0.,1.);
  vec2 p=(UV*2.-1.);
  p*=1.25;
  float r=length(p*vec2(.85,1.0));
  float nn=noise(p*3.+vec2(sd,-TIME*2.))*.6+noise(p*6.-sd)*.4;
  float lobe=(.55+.45*smoothstep(0.,.5,t))*(1.-.35*t)+(nn-.5)*.5;
  float body=1.-smoothstep(lobe*.7,lobe,r);
  vec3 hot=mix(vec3(1.,.78,.32),vec3(1.,.40,.06),smoothstep(0.,.7,r/max(lobe,.01)+t*.6));
  vec3 smoke=vec3(.10,.07,.055);
  col=mix(hot,smoke,smoothstep(.10,.60,t+nn*.2));
  float qedge=1.-smoothstep(.40,.82,max(abs(UV.x*2.-1.),abs(UV.y*2.-1.)));
  a=body*qedge*(1.-smoothstep(.55,1.,t))*.62*smoothstep(0.,.04,age);
 }
 vec2 hd=(SCREEN_UV-hero_uv)*vec2(aspect,1.);
 a*=mix(layer==1?.12:.35,1.,smoothstep(.08,.22,length(hd)));
 ALBEDO=col;
 ALPHA=clamp(a,0.,1.);
}
