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
  ALBEDO=c;ALPHA=clamp(ring*fade*.85*impact_data.w,0.,1.);
 }else if(!cold && !arc){
  // Fireball burst (U-57): a round fire swells in .1 s (age .33 of a .3 s life), holds, shrinks and cools to dark red by .25 s,
  // while sparks fly outward. Edge 1.0 is the core's explosion radius; the body never passes .9 of it.
  float ang=atan(p.y,p.x);
  float swell=1.-pow(1.-clamp(age/.33,0.,1.),3.);
  float shrink=1.-.30*smoothstep(.50,1.,age);
  float lobes=noise(vec2(cos(ang),sin(ang))*2.6+vec2(age*4.,3.))*.5+n*.5;
  float edge=swell*shrink*(.70+.20*lobes);
  float rn=r/max(edge,.001);
  float body=1.-smoothstep(.80,1.06,rn+(n-.5)*.18);
  float cool=smoothstep(.30,.85,age);
  float level=(1.-smoothstep(.62,1.,age))*mix(1.,.55,cool);
  vec3 c_core=vec3(.95,.58,.14);vec3 c_body=vec3(1.,.38,.04);vec3 c_rim=vec3(.55,.07,.008);
  vec3 col=mix(c_core,c_body,smoothstep(.0,.40,rn+cool*.35));
  col=mix(col,c_rim,smoothstep(.55,1.,rn+cool*.30));
  // A meteor landing (gain below the normal 1.0) is a deeper orange: less green, so the stack under glow + contrast does not clip yellow.
  col*=mix(vec3(1.,.66,.55),vec3(1.),smoothstep(.5,1.,impact_data.w));
  float fill=body*(.34+.16*n+.14*(1.-smoothstep(.0,.8,rn)))*level*impact_data.w;
  // Sparks: 14 radial dashes thrown out past the fire edge, each with its own speed and length.
  float cells=14.;
  float cid=floor((ang/6.2831853+.5)*cells);
  float h1=hash(vec2(cid,5.3));float h2=hash(vec2(cid,9.1));
  float acen=((cid+.5)/cells-.5)*6.2831853+(h2-.5)*.10;
  float da=abs(atan(sin(ang-acen),cos(ang-acen)))*r;
  float sr=mix(.30,.94,pow(clamp(age*1.5,0.,1.),.6)*(.62+.38*h1));
  float spark=(1.-smoothstep(.012,.030,da))*(1.-smoothstep(.0,.075+.05*h2,abs(r-sr)))*(1.-smoothstep(.45,.95,age))*step(.35,h1);
  ALBEDO=col*fill+vec3(.95,.62,.20)*spark*.75*impact_data.w;
  ALPHA=clamp(fill+spark*impact_data.w,0.,1.)*(1.-smoothstep(.88,1.,r));
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
