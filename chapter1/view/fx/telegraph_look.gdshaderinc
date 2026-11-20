// Telegraph look values, one place (U-56, U-62). Included by telegraph_common.gdshaderinc and telegraph_cue.gdshader.
// U-56 look values (one place). Reference: the Sacrata recording measured line rgb ~(185,52,60) (S .72, V .73, hue ~0 deg),
// floor fill rgb ~(100,34,37) (V .4), 2-4 px lines, the burst brighter than the warning. Ours before: line (255,46,79), V 1.0.
// Colours are sRGB screen values; the passes convert them.
const vec3 TELE_LINE_RGB = vec3(0.80, 0.18, 0.17);     // line, calm
const vec3 TELE_LINE_HOT_RGB = vec3(0.98, 0.30, 0.24); // line in the last ticks (the only moment it gets bright)
const vec3 TELE_HALO_RGB = vec3(0.10, 0.01, 0.02);     // dark rim next to the line (reads on bright floors, and as a brightness step)
const vec3 TELE_FILL_RGB = vec3(0.30, 0.03, 0.035);    // dark crimson floor wash (alpha blended, never additive)
const float TELE_LINE_HALF = 0.028;   // m, half width of the line at weight 1.0 (was .035)
const float TELE_RAY_TAPER = 0.40;    // a ray ends this much thinner and fainter than at the enemy
const float TELE_RAY_TIP = 0.07;      // m, radius of the ray's head dot (was .15)
const float TELE_FILL_A_MIN = 0.55;   // fill strength at progress 0 as a share of the full value; it rises to 1.0 at p = 1
const float TELE_FILL_NORMAL = 0.20;  // full fill alpha, normal enemy (was .28)
const float TELE_FILL_HEAVY = 0.24;   // elite body (was .32)
const float TELE_FILL_STRIKE = 0.28;  // floor strike / boss hazard (was .36)
const float TELE_RAY_FILL = 0.085;    // faint corridor of a ranged volley (was .10)
// U-62 body cue of a normal enemy (no floor telegraph for them): small pulse at the body, fills with the windup, bursts at the shot.
const float TELE_CUE_RADIUS = 0.24;   // m (diameter ~.5), the whole cue stays inside this
const float TELE_CUE_ALPHA = 0.85;
