shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled;
// Preserve instance scale when billboarding (Godot4.5 spatial shader built-ins).
// https://docs.godotengine.org/en/4.5/tutorials/shaders/shader_reference/spatial_shader.html
varying vec4 bolt_data;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+1.),f.x),f.y);}
void vertex(){
 bolt_data=INSTANCE_CUSTOM;
 vec3 scale=vec3(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz),length(MODEL_MATRIX[2].xyz));VERTEX*=scale;
 float a=bolt_data.x*6.2831853-3.14159265;
 VERTEX.xy=mat2(vec2(cos(a),sin(a)),vec2(-sin(a),cos(a)))*VERTEX.xy;
 MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
}
void fragment(){
 vec2 p=vec2((UV.x-.68)*2.,(UV.y-.5)*2.);
 float n=noise(vec2(p.x*9.-TIME*16.+bolt_data.w*7.,p.y*11.));
 // Fire nose remains at the existing paid UV origin; no geometry shift.
 float tip=exp(-dot(p*vec2(5.2,4.8),p*vec2(5.2,4.8)));
 float along=clamp((p.x+1.32)/1.45,0.,1.);
 float width=mix(.055,.25,along)*(1.-smoothstep(.02,.38,p.x));
 float center=sin(p.x*12.-TIME*21.+bolt_data.w*5.)*.035*(1.-along);
 float tail=(1.-smoothstep(width*.25,width,abs(p.y+center)))*smoothstep(-1.36,-1.05,p.x)*(1.-smoothstep(.06,.30,p.x));
 float filament=(1.-smoothstep(.008,.040,abs(p.y+center)))*smoothstep(-1.15,-.45,p.x)*(1.-smoothstep(.0,.16,p.x));
 vec2 rim=smoothstep(vec2(.02),vec2(.10),UV)*(1.-smoothstep(vec2(.90),vec2(.98),UV));
 float support=rim.x*rim.y;
 float shape=max(tail*(.38+n*.48),tip)*support;
 vec3 color=mix(vec3(.78,.055,.004),vec3(1.,.34,.018),clamp(n+along*.30,0.,1.));
 vec3 core=(vec3(1.,.86,.46)*tip*1.75+vec3(1.,.52,.10)*filament*.35)*support;
 float inten=1.5+bolt_data.z*.8;
 if(bolt_data.z<0. && bolt_data.y<.3){
  // Spell child (core flag child:true, z<0): a short dark angular shard, no tail, ~40% of a bolt's brightness.
  // Ember = ember-red/orange fragment, arc (y=.15) = deep blue fragment. Never the hostile crimson.
  vec2 q=(UV-.5)*2.;
  float yy=q.y-q.x*(bolt_data.w-.5)*.6;
  float up=step(0.,yy);
  float hw=(q.x<.05)?.40*smoothstep(-.80,.05,q.x):.40*(1.-smoothstep(.05,.62,q.x));
  hw*=mix(1.,.5,up*step(.6,fract(q.x*2.3+bolt_data.w*5.)));
  float aa=max(fwidth(yy),.012);
  shape=(1.-smoothstep(hw,hw+aa,abs(yy)))*step(-.80,q.x)*step(q.x,.62)*support;
  if(bolt_data.y>.05){
   color=mix(vec3(.20,.28,.68),vec3(.42,.55,1.),up);
   core=vec3(.55,.66,1.)*(1.-smoothstep(0.,.22,abs(yy)))*shape*.30;
  }else{
   color=mix(vec3(.46,.11,.008),vec3(.80,.28,.03),up);
   core=vec3(.70,.38,.10)*(1.-smoothstep(0.,.22,abs(yy)))*shape*.30;
  }
  inten=.70;
 }else if(bolt_data.y>.3 && bolt_data.y<.8){
  // Keep the paid point at the white nose; the faceted body trails behind.
  p=vec2((UV.x-.5)*2.,(UV.y-.5)*2.);
  float extent=max(0.,.21-abs(p.x+.32)*.39);
  float aa=max(fwidth(p.y),.008);
  float lance=(1.-smoothstep(extent,extent+aa,abs(p.y)))*smoothstep(-1.,-.82,p.x)*(1.-smoothstep(.08,.14,p.x));
  float spine=(1.-smoothstep(.014,.055,abs(p.y)))*smoothstep(-.88,-.7,p.x)*(1.-smoothstep(.03,.13,p.x));
  float ridge=smoothstep(-.025,.025,p.y+p.x*.12);
  shape=lance;
  color=mix(vec3(.05,.32,.56),vec3(.32,.79,.96),ridge);
  core=vec3(.76,.96,1.)*spine*1.65;
 }else if(bolt_data.y>.8){
  float shaft=(1.-smoothstep(.025,.06,abs(p.y)))*smoothstep(-.65,-.48,p.x)*(1.-smoothstep(.15,.27,p.x));
  float head=(1.-smoothstep(.0,.025,abs(p.y)-max(0.,.13-abs(p.x-.05)*.60)))*step(-.13,p.x)*step(p.x,.27);
  // Hostile = threat crimson (#ff2f4f family), never the fire orange used by player spells.
  shape=max(shaft,head);color=vec3(1.,.17,.30);core=vec3(.36,.03,.10)*head;
 }
 if(bolt_data.y<=.3 && bolt_data.z>=0.){
  // Fireball (U-57): a round rolling fire ball and a short, wide flame skirt that breaks into pieces behind it.
  // Layers from inside out: yellow-orange heart / orange body / dark red rim. Nothing is white; the brightest
  // channel stays under .85 after the intensity below. Metres come from the quad (2.3 x .82 m, nose at U .68);
  // the batch scales fire quads 1.45x (evolved 2x), so the ball is about .58 m across in the world.
  float sd=bolt_data.w*37.;
  vec2 m=vec2((UV.x-.68)*2.30,(UV.y-.5)*.82);
  vec2 hc=m-vec2(-.10,0.);
  float hr=length(hc);
  // Cheap bounds first: most of the quad is empty, so skip the noise work there.
  if(hr>.27 && (abs(m.y)>.27 || m.x>-.05 || m.x<-1.05)) discard;
  // The ball rolls: its noise field turns about its own centre, so the outline changes every frame.
  float roll=TIME*7.+sd;
  vec2 rc=mat2(vec2(cos(roll),sin(roll)),vec2(-sin(roll),cos(roll)))*hc;
  float n1=noise(rc*9.+sd);
  float n2=noise(rc*17.-vec2(TIME*5.,sd));
  float lobe=.78+.40*n1+.10*(n2-.5);
  float d=hr/(.19*lobe);
  float ball=1.-smoothstep(.86,1.08,d);
  vec3 ballcol=mix(vec3(.95,.62,.16),vec3(1.,.36,.035),smoothstep(.0,.32,d+(n2-.5)*.30));
  ballcol=mix(ballcol,vec3(.52,.065,.008),smoothstep(.48,.90,d+(n1-.5)*.25));
  // Flame skirt: starts nearly as wide as the ball, 2.2 ball-widths long, eroding into separate tongues.
  float u=clamp((-m.x-.08)/.88,0.,1.);
  float tn=noise(vec2(m.x*7.+TIME*15.+sd,m.y*9.));
  float tn2=noise(vec2(m.x*13.+TIME*21.-sd,m.y*14.+3.));
  float wob=(tn-.5)*.10*u+sin(m.x*8.-TIME*19.+sd)*.03*u;
  float hw=mix(.185,.02,pow(u,.8))*(.65+.7*tn2);
  float skirt=(1.-smoothstep(hw*.35,hw,abs(m.y+wob)))*step(m.x,-.08)*smoothstep(0.,.05,u);
  skirt*=smoothstep(.10+u*.34,.40+u*.30,tn*.6+tn2*.5)*(1.-smoothstep(.55,1.,u));
  vec3 skirtcol=mix(vec3(1.,.44,.05),vec3(.62,.09,.01),smoothstep(.10,.75,u+(tn2-.5)*.3));
  // A few sparks falling off the skirt (cells scrolling backwards).
  vec2 sc=vec2(m.x*7.+TIME*3.+sd,(m.y+u*.10)*7.);
  vec2 si=floor(sc);vec2 sf=fract(sc)-.5;
  float spk=step(.80,hash(si+sd))*(1.-smoothstep(.07,.17,length(sf-(vec2(hash(si+3.1),hash(si+7.7))-.5)*.5)))*smoothstep(.12,.30,u)*(1.-smoothstep(.70,1.,u))*step(m.x,-.2);
  color=mix(skirtcol,ballcol,ball);
  shape=clamp(max(max(ball,skirt*.95),spk)*support,0.,1.);
  core=(vec3(1.,.66,.20)*(1.-smoothstep(.0,.55,d))*ball*.30+vec3(1.,.62,.16)*spk*.4)*support;
  inten=.66+bolt_data.z*.15;
 }
 ALBEDO=color*shape;EMISSION=(color*shape+core)*inten;ALPHA=clamp(shape,0.,1.);
}
