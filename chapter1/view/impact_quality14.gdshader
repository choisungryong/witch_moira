shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled;
varying vec4 impact_data;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+1.),f.x),f.y);}
void vertex(){impact_data=INSTANCE_CUSTOM;}
void fragment(){
 vec2 p=UV*2.-1.;float r=length(p);if(r>1.)discard;
 float age=impact_data.x,n=noise(p*6.-age*3.);
 bool cold=impact_data.y>.3 && impact_data.y<.8;
 bool arc=impact_data.y>.8;
 if(impact_data.z>.5 && !cold && !arc){
  // A6-2 fire, layer 1 (prepare): custom.z>.5 marks the hero's hollow ground ring. Rim only, no fill, no white.
  float e=1.-pow(1.-clamp(age/.7,0.,1.),2.);
  float rr=mix(.30,.92,e);
  float ring=exp(-pow((r-rr)/.075,2.))*(.55+.45*n);
  float fade=pow(1.-clamp(age,0.,1.),1.3);
  vec3 c=mix(vec3(.80,.09,.006),vec3(1.,.34,.03),ring);
  ALBEDO=c;ALPHA=clamp(ring*fade*.85,0.,1.);
 }else if(!cold && !arc){
  // A6-2 fire, layer 3 (hit): a filled disc swells in .08 s, holds .08 s, then cools to dark red over ~.3 s.
  // Only the middle 20% is hot (display luminance about .85 or less); the outer body stays orange to red.
  float swell=1.-pow(1.-clamp(age/.17,0.,1.),2.);
  float edge=swell*(.90+(n-.5)*.16);
  float body=1.-smoothstep(edge-.30,edge,r);
  float cool=smoothstep(.38,1.,age);
  float level=mix(1.,.22,cool)*(1.-smoothstep(.82,1.,age));
  float hot=exp(-pow(r/max(.20*swell+.05,.05),2.))*(1.-smoothstep(.12,.55,age));
  float shock=exp(-pow((r-edge)*13.,2.))*(1.-smoothstep(.10,.30,age))*.34;
  vec3 c_hot=vec3(1.,.40,.06);vec3 c_mid=vec3(.95,.16,.012);vec3 c_dark=vec3(.34,.025,.003);
  vec3 col=mix(mix(c_hot,c_mid,smoothstep(.10,.42,age)),c_dark,smoothstep(.40,.92,age));
  float shape=(body*(.15+n*.20)+shock)*level*(1.-smoothstep(.88,1.,r));
  ALBEDO=col*shape+vec3(1.,.62,.22)*hot*.30;
  ALPHA=clamp(shape+hot*.30,0.,1.);
 }else{
  float front=smoothstep(.08,.72,age)*(.85+n*.12);
  float heat=(1.-smoothstep(front-.26,front+.15,r))*(1.-age);
  float wave=exp(-pow((r-front)*12.,2.))*(.28+n*.6)*(1.-age);
  float core=exp(-r*7.)*pow(1.-age,3.);
  vec3 color=mix(vec3(.83,.045,.004),vec3(1.,.39,.018),n);
  float shape=heat*(.28+n*.5)+wave*.40;
  vec3 core_color=vec3(1.,.75,.36);
  if(cold){
   float angle_=atan(p.y,p.x);
   float spokes=pow(abs(cos(angle_*6.+sin(r*11.)*.16)),34.);
   float broken=step(.24,noise(p*13.));
   float cracks=spokes*(1.-smoothstep(front-.12,front+.08,r))*smoothstep(.04,.16,r)*broken;
   shape=(wave*.42+cracks*.85)*pow(1.-age,.65);
   color=mix(vec3(.07,.35,.66),vec3(.62,.93,1.),cracks);
   core_color=vec3(.82,.98,1.);
  }else{
   float fissures=pow(abs(sin(atan(p.y,p.x)*9.+r*22.+n*3.)),18.);
   shape=(fissures*heat*.65+wave*.22);color=vec3(.46,.61,1.);core_color=vec3(.80,.88,1.);
  }
  shape*=1.-smoothstep(.88,1.,r);
  ALBEDO=color*shape;EMISSION=color*shape*1.5+core_color*core*1.0;ALPHA=clamp(shape+core*.45,0.,1.);
 }
}
