#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

// Halftone token spiral — the full-bleed field drawn while the assistant is
// generating (and, quieter, for the welcome intro). A screen-space halftone dot
// grid samples a rotating multi-arm spiral field: each dot's size follows how
// deep inside a spiral arm its cell centre sits, and the arms keep sliding
// outward from a glowing core, so the dots read as a stream of tokens being
// emitted. Two star layers twinkle over the whole thing.
//
// Order MUST match kSpiralUniformOrder / buildSpiralUniforms
// (lib/Widgets/gradient/spiral_geometry.dart).
uniform vec4 uIdle;     // rgb flat idle colour, a = 1
uniform vec4 uCanvas;   // rgb canvas tint, a = o (overall fade 0..1)
uniform vec4 uColA;     // rgb hue A (w unused)
uniform vec4 uColB;     // rgb hue B (w unused)
uniform vec4 uStar;     // rgb star / highlight colour, a = star strength (already × o)
uniform vec4 uSpiral;   // xy = centre px, z = arm pitch px (radial gap between arms), w = rotation rad
uniform vec4 uFlow;     // x = outward flow (arm pitches), y = token bead phase rad, z = bead amount 0..1, w = arm count (integer)
uniform vec4 uField;    // x = core radius px, y = outer radius px, z = intensity 0..1, w = halftone cell px
uniform vec4 uTwinkle;  // x = star time s, y = star drift px, z = core glow 0..1, w = hue drift rad

out vec4 fragColor;

const float TAU = 6.28318530718;
const float GRID_ANGLE = 0.384;  // ~22deg rotated halftone screen
const float DOT_GAIN = 1.08;     // full-coverage dot radius, in half-cell units
const float DOT_GAMMA = 0.5;     // dot growth vs coverage (sqrt: area ~ coverage)
const float ARM_WIDTH = 0.62;    // dotted fraction of each arm band

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// One star layer over a jittered grid: at most one star per cell (gated by
// density), each with a ~1px core, a soft halo and its own twinkle rhythm; the
// brightest few also carry a four-point flare. Every part of a star stays inside
// its own cell, so no neighbour lookups are needed.
float starLayer(vec2 p, float cell, float density, float time, float drift) {
  vec2 q = (p + vec2(drift * 0.35, drift)) / cell;
  vec2 id = floor(q);
  float h = hash12(id);
  float gate = step(h, density);
  vec2 jitter = (vec2(hash12(id + 7.1), hash12(id + 3.7)) - 0.5) * 0.5;
  vec2 d = (fract(q) - 0.5 - jitter) * cell;   // px from the star centre
  float r2 = dot(d, d);
  float tw = 0.5 + 0.5 * sin(time * (0.7 + 1.5 * h) + h * TAU);
  tw = 0.2 + 0.8 * tw * tw;
  float core = exp(-r2 * 0.8);
  float halo = exp(-r2 / (cell * cell * 0.012));
  float flareLen = cell * 0.22;
  float flare = max(0.0, 1.0 - abs(d.y) / flareLen) * exp(-abs(d.x) * 1.2)
              + max(0.0, 1.0 - abs(d.x) / flareLen) * exp(-abs(d.y) * 1.2);
  float bright = smoothstep(0.82, 1.0, h / max(density, 1e-3));
  return gate * tw * (core + 0.35 * halo + 0.55 * bright * flare);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float o = uCanvas.a;
  vec3 base = mix(uIdle.rgb, uCanvas.rgb, o);

  float pitch = max(uSpiral.z, 1.0);
  float arms = uFlow.w;
  float coreR = max(uField.x, 1.0);
  float outerR = max(uField.y, coreR + 1.0);
  float cell = max(uField.w, 2.0);

  // Halftone screen: sample the spiral field at the *centre* of this pixel's
  // rotated grid cell, so every dot is one clean disc of a single size.
  float ca = cos(GRID_ANGLE), sa = sin(GRID_ANGLE);
  mat2 toGrid = mat2(ca, -sa, sa, ca);
  mat2 toScreen = mat2(ca, sa, -sa, ca);
  vec2 g = toGrid * p / cell;
  vec2 fc = fract(g) - 0.5;
  vec2 cc = toScreen * ((floor(g) + 0.5) * cell);

  vec2 relc = cc - uSpiral.xy;
  float rc = length(relc);
  float thc = atan(relc.y, relc.x) + uSpiral.w;
  // Archimedean arms: crossing coordinate t is integral on an arm centre. The
  // flow term pushes every arm outward as it grows; `arms` is integral so t is
  // continuous across the atan branch cut.
  float t = rc / pitch - arms * thc / TAU - uFlow.x;
  float across = abs(fract(t) - 0.5) * 2.0;            // 0 on the arm, 1 between arms
  float arm = 1.0 - smoothstep(0.0, ARM_WIDTH, across);
  float env = smoothstep(coreR * 0.35, coreR, rc)      // hollow core...
            * (1.0 - smoothstep(outerR * 0.45, outerR, rc)); // ...thinning out to the edge
  // Token beads: bright packets running outward along each arm, offset per arm.
  float beadWave = 0.5 + 0.5 * sin(rc * (TAU / (pitch * 0.5)) - uFlow.y + floor(t) * 1.9);
  float bead = mix(1.0, 0.15 + 0.85 * beadWave * beadWave, uFlow.z);
  float cov = clamp(arm * env * bead * uField.z * o, 0.0, 1.0);

  float radius = pow(cov, DOT_GAMMA) * DOT_GAIN;
  float dist = length(fc) * 2.0;                        // 1.0 at the cell's inscribed edge
  float aa = 2.4 / cell;                                // ~1.2px edge softness
  float dotm = (1.0 - smoothstep(radius - aa, radius + aa, dist)) * smoothstep(0.0, 0.05, cov);

  // Two hues swirl along the arms; bead peaks flash toward the highlight colour.
  float hueMix = 0.5 + 0.5 * sin(thc + rc / pitch * 0.35 + uTwinkle.w);
  vec3 dotCol = mix(uColA.rgb, uColB.rgb, hueMix);
  float peak = uFlow.z * smoothstep(0.7, 1.0, beadWave * beadWave);
  dotCol = mix(dotCol, uStar.rgb, peak * 0.45);

  // Luminous core the tokens pour out of, breathing gently with the bead phase.
  vec2 rel = p - uSpiral.xy;
  float r2 = dot(rel, rel);
  float breathe = 0.85 + 0.15 * sin(uFlow.y * 0.35);
  float glow = exp(-r2 / (2.0 * coreR * coreR)) * uTwinkle.z * breathe * o;
  vec3 glowCol = mix(uColA.rgb, uColB.rgb, 0.5);

  vec3 col = mix(base, glowCol, glow * 0.55);
  col = mix(col, dotCol, dotm);

  // Starfield: a sparse far layer and a denser near layer drifting at
  // different rates for a little parallax.
  float stars = starLayer(p, 46.0, 0.55, uTwinkle.x, uTwinkle.y)
              + starLayer(p, 27.0, 0.28, uTwinkle.x * 1.3, uTwinkle.y * 1.8);
  col = mix(col, uStar.rgb, clamp(stars * uStar.a, 0.0, 1.0));

  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);        // opaque full-bleed base
}
