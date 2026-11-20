shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled;
// D20 Meteor: the mark on the floor. A plane of 2 x 2 units scaled to 1.3 x the core's radius, so local radius 1.0 is the real
// explosion radius (the soot never passes it).
// custom.x = progress (fall phase: 0..1 over the fall; scorch phase: 0..1 over the scorch seconds), custom.y = phase (0 fall,
// 1 scorch), custom.z = seed.
//  fall    a ragged soot patch that darkens, an orange glow that tightens to the middle and brightens as the ball nears,
//          and a few orange tick marks round the edge (broken, never a closed red ring).
//  scorch  the soot stays, glowing cinders go out one by one, the first flash cools in the first tenth.
varying vec4 mark_data;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+1.),f.x),f.y);}
void vertex(){mark_data=INSTANCE_CUSTOM;}
void fragment(){
 vec2 p=(UV*2.-1.)*1.3;
 float r=length(p);
 float t=clamp(mark_data.x,0.,1.);
 float sd=mark_data.z*31.;
 float ang=atan(p.y,p.x);
 float n=noise(p*3.2+sd);
 float edge=1.-smoothstep(.80+.10*n,1.0+.02*n,r);          // ragged soot disc, inside the real radius
 vec3 col=vec3(.04,.025,.015);
 float a=0.;
 if(mark_data.y<.5){
  a=edge*mix(.50,.78,sqrt(t))*(.75+.25*n);
  float sigma=mix(.95,.32,t);
  float glow=exp(-pow(r/sigma,2.))*mix(.30,1.,t*t);
  col=mix(col,vec3(.70,.27,.04),clamp(glow*1.4,0.,1.));
  a=max(a,glow*.50*edge);
  // Orange tick marks round the edge, about half of them missing.
  float cells=26.;
  float cid=floor((ang/6.2831853+.5)*cells);
  float on=step(.72,hash(vec2(cid,sd)));
  float tick=on*(1.-smoothstep(.015,.035,abs(r-.94)))*(.4+.6*t)*step(.3,fract((ang/6.2831853+.5)*cells))*step(fract((ang/6.2831853+.5)*cells),.7);
  col=mix(col,vec3(.70,.32,.05),tick);
  a=max(a,tick*.7*t);
 }else{
  float fade=1.-smoothstep(.55,1.,t);
  a=edge*.58*fade*(.75+.25*n);
  float flash=exp(-r*r*2.5)*(1.-smoothstep(.0,.16,t));
  // Cinders: a grid of cells, each with its own time of going out.
  vec2 g=p*5.5+sd;
  vec2 gi=floor(g);vec2 gf=fract(g)-.5;
  float h=hash(gi);
  vec2 jit=(vec2(hash(gi+2.3),hash(gi+5.9))-.5)*.5;
  float die=.25+.65*hash(gi+9.1);
  float cinder=step(.45,h)*(1.-smoothstep(.10,.22,length(gf-jit)))*(1.-smoothstep(die-.12,die,t))*edge;
  cinder*=.65+.35*sin(TIME*18.+h*40.);
  col=mix(col,vec3(.70,.26,.03),clamp(cinder+flash,0.,1.));
  a=max(a,max(cinder*.6,flash*.22));
 }
 ALBEDO=col;
 ALPHA=clamp(a*mark_data.w,0.,1.);
}
