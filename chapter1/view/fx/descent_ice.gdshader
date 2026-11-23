shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;
// D24 6.4 Absolute Zero: the ice skin of a frozen body, one camera-facing quad per frozen enemy (a MultiMesh of up to 64).
// The body stays visible inside: the fill is thin and cold blue, the edges and facet lines are the strong part. The cracks grow with
// each of the eight pulses and the whole shell goes at the break. Cold colours only (never the gold of a stun).
// custom.x = age since it appeared (s), custom.y = seed, custom.z = crack level 0..1, custom.w = break progress 0..1 (0 = intact).
varying vec4 id;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+1.),f.x),f.y);}
void vertex(){
 id=INSTANCE_CUSTOM;
 vec3 sc=vec3(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz),length(MODEL_MATRIX[2].xyz));
 VERTEX*=sc;
 MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
}
void fragment(){
 float sd=id.y*29.;
 float grow=clamp(id.x/.22,0.,1.);
 vec2 p=(UV*2.-1.);
 p.y=(p.y+.1)/max(.25,grow);                       // rises out of the floor
 float ang=atan(p.y,p.x);
 float lobe=.62+.16*noise(vec2(ang*1.9+sd,sd))+.10*abs(sin(ang*2.5+sd));
 float r=length(p*vec2(1.0,.82));
 float d=r/lobe;
 float body=1.-smoothstep(.90,1.0,d);
 float rimline=smoothstep(.70,.92,d)*body;
 vec2 g=p*3.2+sd;
 float facet=1.-smoothstep(0.,.06,abs(fract(g.x*.8+g.y*.55)-.5)*2.-.80+.0);
 float f2=1.-smoothstep(0.,.05,abs(fract(g.x*-.5+g.y*.9+.3)-.5)*2.-.82);
 float lines=max(facet,f2)*.5;
 float cr=1.-smoothstep(0.,.045,abs(noise(p*3.7+sd*2.)-.5));
 float crack=cr*smoothstep(.05,.5,id.z)*smoothstep(.1,.6,noise(p*2.+sd));
 // A11 5.2: edge .30 -> .22, grain .16 -> .10, crack .45 -> .35; the crack is a pale cyan, not white (white stays for the break)
 vec3 col=mix(vec3(.45,.74,.92),vec3(.74,.92,1.),rimline*.8+lines*.5);   // A11 5.2 (extra): the edge is cyan, not white
 col=mix(col,vec3(.80,.93,1.),crack*.85);
 float a=body*(.05+.18*rimline+.08*lines)+crack*body*.30;
 float br=id.w;
 a*=(1.-smoothstep(.0,.35,br));
 col=mix(col,vec3(1.),smoothstep(.0,.08,br)*(1.-smoothstep(.08,.2,br))*.7);
 a=max(a,body*smoothstep(0.,.06,br)*(1.-smoothstep(.06,.18,br))*.8);
 a*=smoothstep(0.,.05,id.x);
 ALBEDO=col*.54;
 ALPHA=clamp(a,0.,.7);
}
