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

// srcOver one blob: alpha = blob.w * the [0,0.4,1]->[1,1,0] radial falloff.
vec3 blob(vec3 col, vec2 p, vec4 b, vec4 c) {
  float d = distance(p, b.xy) / b.z;
  float a = clamp((1.0 - d) / 0.6, 0.0, 1.0) * b.w;
  return mix(col, c.rgb, a);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec3 col = uIdle.rgb;
  col = mix(col, uCanvas.rgb, uCanvas.a);   // tint fades in with o
  col = blob(col, p, uB0, uC0);
  col = blob(col, p, uB1, uC1);
  col = blob(col, p, uB2, uC2);
  col = blob(col, p, uB3, uC3);
  col = blob(col, p, uB4, uC4);
  col = blob(col, p, uB5, uC5);
  fragColor = vec4(col, 1.0);               // opaque full-bleed base
}
