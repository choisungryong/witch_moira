shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;
// D24 5.4 Armageddon: a falling rock fragment. Same grammar as the evolved Meteor's ball (a camera-facing quad turned along the fall,
// tail to -x) but a different thing: a dark angular basalt body with glowing cracks and a white-hot leading edge, a thick flame
// skirt and a smoke ribbon. At scale 1 the rock radius is 2.0 m and the quad is 16 x 7.2 m (the Meteor ball is 0.8 m with a 5.6 m
// tail); the host scales the quad to the fragment's own radius (big 1.8 m, small 1.1 m: 3.6 / 2.2 m across, tail about 10 / 6 m).
// custom.x = fall direction (radians on the screen), custom.y = fall progress 0..1, custom.z = seed.
// The hero stays readable: where the quad overlaps the hero on the screen its alpha drops to 28 %.
uniform vec2 hero_uv = vec2(-1.0);
uniform float aspect = 1.7778;
varying vec4 rd;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+1.),f.x),f.y);}
void vertex(){
 rd=INSTANCE_CUSTOM;
 vec3 sc=vec3(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz),length(MODEL_MATRIX[2].xyz));
 VERTEX*=sc;
 float a=rd.x;
 VERTEX.xy=mat2(vec2(cos(a),sin(a)),vec2(-sin(a),cos(a)))*VERTEX.xy;
 MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
}
void fragment(){
 float sd=rd.z*37.;
 vec2 q=vec2((UV.x-.80)*8.,(UV.y-.5)*3.6)/1.0;     // in rock radii (the quad is 8 x 3.6 radii)
 float r=length(q);
 vec2 rim=smoothstep(vec2(.01),vec2(.08),UV)*(1.-smoothstep(vec2(.92),vec2(.99),UV));
 float support=rim.x*rim.y;
 float ang=atan(q.y,q.x);
 // angular silhouette
 float lobe=.78+.20*noise(vec2(ang*1.7+sd,sd))+.10*abs(sin(ang*3.+sd*.7))+.06*noise(vec2(ang*5.,sd+4.));
 float d=r/lobe;
 float body=1.-smoothstep(.93,1.0,d);
 // dark basalt with glowing cracks, tumbling slowly
 float roll=TIME*1.6+sd;
 vec2 rc=mat2(vec2(cos(roll),sin(roll)),vec2(-sin(roll),cos(roll)))*q;
 float n1=noise(rc*2.1+sd);
 float n2=noise(rc*4.3-sd);
 float crack=1.-smoothstep(0.,.07,abs(n1-.5));
 crack=max(crack,(1.-smoothstep(0.,.05,abs(n2-.5)))*.6);
 vec3 rock=mix(vec3(.07,.05,.045),vec3(.20,.12,.08),n2);
 float front=smoothstep(-.2,.9,q.x/max(r,.001))*smoothstep(.45,1.0,d);     // leading side is heated
 vec3 col=mix(rock,vec3(1.,.42,.07),clamp(crack*(.55+.45*sin(TIME*9.+sd+n1*6.)),0.,1.)*.95);
 col=mix(col,vec3(1.,.62,.20),front*.85);
 col=mix(col,vec3(.95,.78,.45),smoothstep(.82,.97,d)*front);
 // flame skirt: about 5 radii long, eroding into tongues
 float u=clamp((-q.x-.4)/6.2,0.,1.);
 float tn=noise(vec2(q.x*.9+TIME*13.+sd,q.y*1.3));
 float tn2=noise(vec2(q.x*1.8+TIME*19.-sd,q.y*2.2+3.));
 float wob=(tn-.5)*1.1*u+sin(q.x*1.1-TIME*16.+sd)*.3*u;
 float hw=mix(1.15,.10,pow(u,.8))*(.65+.7*tn2);
 float skirt=(1.-smoothstep(hw*.35,hw,abs(q.y+wob)))*step(q.x,-.4)*smoothstep(0.,.03,u);
 skirt*=smoothstep(.08+u*.30,.38+u*.28,tn*.6+tn2*.5)*(1.-smoothstep(.5,1.,u));
 vec3 skirtcol=mix(vec3(1.,.50,.07),vec3(.62,.09,.01),smoothstep(.08,.75,u+(tn2-.5)*.3));
 float shw=hw*1.7+.4;
 float smoke=(1.-smoothstep(shw*.5,shw,abs(q.y+wob*1.3)))*step(q.x,-.8)*(1.-smoothstep(.2,1.,u))*(.35+.65*noise(vec2(q.x*.7+TIME*5.+sd,q.y*.9)));
 vec2 sc=vec2(q.x*.7+TIME*2.5+sd,(q.y+u*.8)*.7);
 vec2 si=floor(sc);vec2 sf=fract(sc)-.5;
 float spk=step(.74,hash(si+sd))*(1.-smoothstep(.07,.17,length(sf-(vec2(hash(si+3.1),hash(si+7.7))-.5)*.5)))*smoothstep(.1,.3,u)*(1.-smoothstep(.75,1.,u))*step(q.x,-1.4);
 float halo=exp(-r*r*.16)*.26;
 float fire=clamp(max(skirt*.95,spk),0.,1.);
 vec3 rgb=mix(skirtcol,col,body);
 rgb=mix(rgb,vec3(.95,.62,.20),spk*(1.-body)*.6);
 rgb=mix(vec3(.12,.075,.055),rgb,clamp(max(fire,body)*2.,0.,1.));
 rgb=mix(rgb,vec3(.90,.36,.05),halo*(1.-max(fire,body)));
 float alpha=max(max(max(fire,body),smoke*.40),halo)*support*smoothstep(0.,.08,rd.y+.05);
 vec2 hd=(SCREEN_UV-hero_uv)*vec2(aspect,1.);
 float clear=smoothstep(.07,.17,length(hd));
 alpha*=mix(.28,1.,clear);
 ALBEDO=rgb*.78;
 ALPHA=clamp(alpha,0.,1.);
}
