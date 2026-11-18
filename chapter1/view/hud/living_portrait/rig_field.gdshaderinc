// Shared displacement field of the body rig (image pixels). Everything is a smooth function of the pixel position,
// so the layers that use it (legs, back drape, skirt, left arm) stay joined.
//  - above the waist the displacement blends from the pelvis offset to the chest offset (spine)
//  - below the waist the pelvis offset fades to zero at the ankles (the feet stay on the floor): legs tilt about the feet
//  - hip_l_dy / hip_r_dy lower or raise each hip (pelvis tilt); the loaded side rises, the unloaded side drops
//  - the knees get a bump per leg: sideways (knee_*) and downward (knee_*_dy), the unloaded knee comes forward
//  - arm_extra lifts only the upper part of the left arm (the hand stays on the hip)

uniform vec2 pelvis = vec2(0.0);
uniform vec2 chest = vec2(0.0);
uniform float knee_l = 0.0;
uniform float knee_r = 0.0;
uniform float knee_l_dy = 0.0;
uniform float knee_r_dy = 0.0;
uniform float hip_l_dy = 0.0;
uniform float hip_r_dy = 0.0;
uniform float arm_extra = 0.0;
uniform float y_hip = 470.0;
uniform float y_chest = 300.0;
uniform float y_ankle = 1380.0;
uniform float y_knee = 870.0;
uniform float split_x = 470.0;
uniform float side_force = -1.0; // -1: leg side by x position; 0 left leg, 1 right leg (separate leg layers)

vec2 body_disp(vec2 p) {
	vec2 d;
	float side = side_force >= 0.0 ? side_force : smoothstep(split_x - 30.0, split_x + 30.0, p.x);
	if (p.y < y_hip) {
		float u = smoothstep(0.0, 1.0, clamp((y_hip - p.y) / (y_hip - y_chest), 0.0, 1.0));
		d = mix(pelvis, chest, u);
		d.y += arm_extra * smoothstep(500.0, 380.0, p.y);
		d.y += mix(hip_l_dy, hip_r_dy, side) * smoothstep(y_hip - 90.0, y_hip, p.y);
	} else {
		float tl = clamp((p.y - y_hip) / (y_ankle - y_hip), 0.0, 1.0);
		float w = 1.0 - (3.0 * tl * tl - 2.0 * tl * tl * tl);
		d = pelvis * w;
		d.y += mix(hip_l_dy, hip_r_dy, side) * w;
		float kb = exp(-pow((p.y - y_knee) / 130.0, 2.0));
		d.x += mix(knee_l, knee_r, side) * kb;
		d.y += mix(knee_l_dy, knee_r_dy, side) * kb;
	}
	return d;
}
