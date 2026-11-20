shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;
// D20 Meteor: the big falling fire ball (also the small launch streak, drawn at a fraction of the size).
// Parts of the fireball shader at 2.75x: a rolling ball (yellow-orange heart / orange body / dark red rim), a flame skirt that
// breaks into tongues along the fall (3.5 ball widths), dark smoke behind it and sparks. Nothing is white and no channel
// passes .85. The quad is 8 x 3.4 m, the ball centre sits at U .80, the tail points to -x (the quad is turned by custom.x,
// radians, so +x runs along the fall on the screen). custom.y = fall progress 0..1, custom.z = seed.
varying vec4 ball_data;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+1.),f.x),f.y);}
void vertex(){
 ball_data=INSTANCE_CUSTOM;
 vec3 sc=vec3(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz),length(MODEL_MATRIX[2].xyz));
 VERTEX*=sc;
 float a=ball_data.x;
 VERTEX.xy=mat2(vec2(cos(a),sin(a)),vec2(-sin(a),cos(a)))*VERTEX.xy;
 MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
}
void fragment(){
 float sd=ball_data.z*37.;
 vec2 q=vec2((UV.x-.80)*8.,(UV.y-.5)*3.4)/.8;   // ball radii
 float r=length(q);
 vec2 rim=smoothstep(vec2(.01),vec2(.08),UV)*(1.-smoothstep(vec2(.92),vec2(.99),UV));
 float support=rim.x*rim.y;
 float roll=TIME*6.+sd;
 vec2 rc=mat2(vec2(cos(roll),sin(roll)),vec2(-sin(roll),cos(roll)))*q;
 float n1=noise(rc*1.7+sd);
 float n2=noise(rc*3.4-vec2(TIME*5.,sd));
 float lobe=.80+.38*n1+.10*(n2-.5);
 float d=r/lobe;
 float ball=1.-smoothstep(.86,1.08,d);
 vec3 ballcol=mix(vec3(.95,.50,.10),vec3(1.,.36,.035),smoothstep(.0,.32,d+(n2-.5)*.30));
 ballcol=mix(ballcol,vec3(.52,.065,.008),smoothstep(.48,.90,d+(n1-.5)*.25));
 // Flame skirt, 3.5 ball widths (7 radii) long, eroding into separate tongues.
 float u=clamp((-q.x-.2)/7.,0.,1.);
 float tn=noise(vec2(q.x*1.3+TIME*14.+sd,q.y*1.7));
 float tn2=noise(vec2(q.x*2.4+TIME*21.-sd,q.y*2.8+3.));
 float wob=(tn-.5)*.9*u+sin(q.x*1.5-TIME*18.+sd)*.25*u;
 float hw=mix(1.0,.08,pow(u,.8))*(.65+.7*tn2);
 float skirt=(1.-smoothstep(hw*.35,hw,abs(q.y+wob)))*step(q.x,-.2)*smoothstep(0.,.03,u);
 skirt*=smoothstep(.10+u*.34,.40+u*.30,tn*.6+tn2*.5)*(1.-smoothstep(.55,1.,u));
 vec3 skirtcol=mix(vec3(1.,.44,.05),vec3(.62,.09,.01),smoothstep(.10,.75,u+(tn2-.5)*.3));
 // Smoke: a wider dark ribbon behind the flames.
 float shw=hw*1.5+.3;
 float smoke=(1.-smoothstep(shw*.5,shw,abs(q.y+wob*1.3)))*step(q.x,-.6)*(1.-smoothstep(.25,1.,u))*(.35+.65*noise(vec2(q.x*.9+TIME*6.+sd,q.y*1.1)));
 // Sparks falling off the tail.
 vec2 sc=vec2(q.x*.8+TIME*2.5+sd,(q.y+u*.8)*.8);
 vec2 si=floor(sc);vec2 sf=fract(sc)-.5;
 float spk=step(.78,hash(si+sd))*(1.-smoothstep(.07,.17,length(sf-(vec2(hash(si+3.1),hash(si+7.7))-.5)*.5)))*smoothstep(.12,.30,u)*(1.-smoothstep(.75,1.,u))*step(q.x,-1.);
 float halo=exp(-r*r*.30)*.22;
 float fire=clamp(max(max(ball,skirt*.95),spk),0.,1.);
 vec3 col=mix(skirtcol,ballcol,ball);
 col=mix(col,vec3(.95,.62,.20),spk*(1.-ball)*.6);
 col=mix(vec3(.12,.075,.055),col,clamp(fire*2.,0.,1.));
 col=mix(col,vec3(.90,.36,.05),halo*(1.-fire));
 float alpha=max(max(fire,smoke*.38),halo)*support*smoothstep(0.,.08,ball_data.y+.03);
 ALBEDO=col*.74;   // the production glow (threshold .9) turned the .86 heart yellow; .74 keeps the heart orange
 ALPHA=clamp(alpha,0.,1.);
}
