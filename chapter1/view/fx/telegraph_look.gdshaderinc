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
// D-boss-finale (A-boss-finale-screen): styles of the finale's floor shapes, written in the instance colour .r. Same crimson, only the form differs
// so that the four read apart without colour: floor strike (ring, radial fill, style 2), storm (a second thin ring outside, 3), landing
// (clockwise sweep and eight ticks inside the edge, 4), slam (three chevrons along the bar, 5).
const float TELE_STYLE_STORM = 3.0;
const float TELE_STYLE_LAND = 4.0;
const float TELE_STYLE_SLAM = 5.0;
const float TELE_STORM_GAP = 0.14;     // m, the storm's second ring outside the first
const float TELE_STORM_WEIGHT = 0.70;  // its line weight against the first
const float TELE_LAND_BASE = 0.30;     // fill of the part the sweep has not reached yet, as a share of the swept part
const float TELE_LAND_TICK_LEN = 0.28; // m, the eight ticks inside the edge (the chain's links)
const float TELE_CHEVRON_LEN = 0.80;   // m, how far the arms of a chevron run back from its tip
const float TELE_CHEVRON_DARK = 0.45;  // chevron strength before the fill front reaches it (it is 0.95 after)
