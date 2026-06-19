#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

// Order MUST match buildMeshUniforms (lib/Widgets/gradient/mesh_geometry.dart).
uniform vec4 uIdle;    // rgb, a=1
uniform vec4 uCanvas;  // rgb, a=o (fade)
uniform vec4 uB0; uniform vec4 uB1; uniform vec4 uB2;
uniform vec4 uB3; uniform vec4 uB4; uniform vec4 uB5;  // xy=centre px, z=radius px, w=alpha
uniform vec4 uC0; uniform vec4 uC1; uniform vec4 uC2;
uniform vec4 uC3; uniform vec4 uC4; uniform vec4 uC5;  // rgb colour (w unused)

out vec4 fragColor;

// One blob's field contribution: a compact, smooth (Wyvill) falloff scaled by the
// blob's alpha (blob.opacity * fade o). Returns colour*weight in rgb, weight in a,
// so the six can be summed into coverage + coverage-weighted colour.
vec4 blobField(vec2 p, vec4 b, vec4 c) {
  float d2 = dot(p - b.xy, p - b.xy);
  float r = b.z;                               // radius comes fully-sized from Dart
  float x = clamp(1.0 - d2 / (r * r), 0.0, 1.0);
  float g = x * x * x * b.w;                    // weight; fades with o via b.w
  return vec4(c.rgb * g, g);
}

void main() {
  vec2 p = FlutterFragCoord().xy;

  // Base: flat idle, with the canvas tint faded in by o (uCanvas.a == o).
  vec3 base = mix(uIdle.rgb, uCanvas.rgb, uCanvas.a);

  // Accumulate the six blobs -> coverage (a) + coverage-weighted colour (rgb).
  vec4 acc = blobField(p, uB0, uC0) + blobField(p, uB1, uC1)
           + blobField(p, uB2, uC2) + blobField(p, uB3, uC3)
           + blobField(p, uB4, uC4) + blobField(p, uB5, uC5);
  float cov = acc.a;
  vec3 mesh = cov > 1e-4 ? acc.rgb / cov : base;
  float alpha = clamp(cov, 0.0, 1.0);

  // Screen-space halftone dissolve: the dot radius tracks coverage, so dense
  // cores read solid and the soft edges break into shrinking dots.
  const float DOT = 13.0;      // dot cell, logical px
  const float ANGLE = 0.384;   // ~22deg rotated screen
  const float GAMMA = 0.60;    // dots all-over vs edge-only
  const float AA = 0.41;       // dot softness
  float ca = cos(ANGLE), sa = sin(ANGLE);
  vec2 rp = mat2(ca, -sa, sa, ca) * p;
  vec2 fc = fract(rp / DOT) - 0.5;
  float dist = length(fc) * 2.0;
  float radius = pow(alpha, GAMMA) * 1.45;
  float dotm = smoothstep(radius, radius - AA, dist);

  vec3 col = mix(base, mesh, dotm);
  col += mesh * smoothstep(0.55, 1.0, alpha) * 0.08;   // faint luminous core
  // (No fine grain: the 38px glass BackdropFilter over this mesh averages any
  //  per-pixel dither to ~0, so computing it per fragment was wasted GPU work.)
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);         // opaque full-bleed base
}
