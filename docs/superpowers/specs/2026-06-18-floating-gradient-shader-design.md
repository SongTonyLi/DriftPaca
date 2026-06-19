# Floating gradient background — one-pass fragment shader

- **Date:** 2026-06-18
- **Status:** Approved, ready for implementation plan
- **Component:** `lib/Widgets/floating_gradient_background.dart` (the "mesh" background)

## Context

The app's background is `FloatingGradientBackground`: a `CustomPainter` ("mesh")
that, **only while the assistant is generating**, fades in a drifting field of six
soft radial-gradient blobs over a tinted canvas, then fades back to a flat
`idleColor` and stops ticking (zero frames at idle). It is driven by a single
`Ticker` + a `ValueNotifier<int>` repaint signal, capped at 30fps, and is placed
at the bottom of the `Stack` in `lib/Pages/main_page.dart` behind a transparent
scaffold.

Per painted frame (≤30fps, only while generating + the ~8s fade-out), the current
painter does:

- `drawRect(idleColor)` — full-screen fill
- `drawRect(canvas, alpha: o)` — full-screen fill
- six × `RadialGradient(...).createShader(rect)` + `drawCircle` — each circle radius
  `0.76–0.95×` the shortest side

Two costs follow:

1. **Fill-rate / overdraw** — six big alpha-blended radial gradients over two
   full-screen rects ≈ **~8× the screen repainted per frame** (more on a tablet).
   On mobile this blend bandwidth dominates power draw.
2. **Per-frame CPU allocation** — `RadialGradient(...).createShader()` runs **6× per
   frame** (~540×/sec), each building a fresh gradient LUT → GC churn.

## Goal

Cut the power cost of the effect **without any visible change** to its look or
motion. Specifically: collapse the ~8× overdraw to ~1× and eliminate the per-frame
shader allocations, while keeping the blob drift, colors, fade, speed easing, and
the "zero frames at idle" behavior **pixel- and behavior-identical**.

## Non-goals

- No redesign of the visual (particles, etc.) — rejected; we keep today's mesh.
- No change to motion character (independent per-blob drift stays exactly as-is).
- No change to the color/mode pipeline (`mode_palette.dart`, `gradient_presets.dart`,
  `gradient_settings.dart`) or to where/how the widget is mounted.
- No change to the generating-gate / ticker scheduling logic.

## Decision history (why this approach)

- **Particles** — rejected. "Dense particles" can cost *more* fill than the blobs;
  swapping shape does not save power by itself.
- **Bake & drift** (cache the mesh once, transform the whole image per frame) —
  rejected. Biggest per-frame win, but it can only move the field as a rigid body;
  the independent blob slide is lost. User wants today's motion kept.
- **Atlas + half-res** (Path B) — viable, kept as fallback. `drawAtlas` of a cached
  sprite removes the CPU allocation but a texture sample costs ~the same per pixel
  as a gradient sample, so the *fill* only shrinks via a half-resolution offscreen,
  which leans on a per-frame `toImageSync`.
- **One-pass fragment shader** (Path A) — **chosen.** Replaces the six gradient draws
  with a single full-screen pass: ~1× fill, zero per-frame allocations, pixel-identical
  look, and no per-frame offscreen. The cost is one `.frag` asset + uniform plumbing.

## The contract (must stay identical)

- **Idle (`opacity <= 0`)**: paint a single flat `idleColor` rect; ticker stays
  stopped; **zero scheduled frames**. (Unchanged from today.)
- **Drift**: `blobPlacement(blob, phase, size)` — sin/cos drift + the `1 + 0.10·sin`
  radius breathing — stays in Dart and is computed every frame. Motion unchanged.
- **Look**: each blob is its color (A or B) at alpha `blob.opacity · o`, solid from
  centre to `0.4·r`, then linear falloff to `0` at `r`; composited **srcOver in blob
  order** over the `canvas` tint (alpha `o`) over the opaque `idleColor`.
- **Colors / fade / speed** read live from `Mesh` (`a`, `b`, `canvas`, `phase`,
  `opacity`) exactly as now — they simply become uniform values.

## Design

### 1. Shader — `shaders/mesh.frag`

Single full-screen fragment shader. Preamble:

```glsl
#version 460 core
#include <flutter/runtime_effect.glsl>
precision mediump float;
```

**Uniforms** (flat float buffer, filled by the Dart side in a fixed agreed order):

| name | type | meaning |
|------|------|---------|
| `uSize` | vec2 | canvas size in px |
| `uIdle` | vec4 | opaque flat base, rgba (a = 1) |
| `uCanvas` | vec4 | tint; rgb = canvas, **a = `o`** (fade) |
| `uBlob[6]` | vec4 ×6 | per blob: `(cx, cy, r, blob.opacity·o)` |
| `uColor[6]` | vec4 ×6 | per blob: `(r, g, b, _)` — rgb in 0..1, w unused |

`uColor` is **vec4, not vec3**, to avoid std140 vec3-array padding pitfalls (see
Risks). Total = 2 + 4 + 4 + 24 + 24 = **58 floats**.

**Per-pixel logic:**

```glsl
void main() {
  vec2 p = FlutterFragCoord().xy;
  vec3 col = uIdle.rgb;
  col = mix(col, uCanvas.rgb, uCanvas.a);              // canvas tint fades in with o
  for (int i = 0; i < 6; i++) {
    float d = distance(p, uBlob[i].xy) / uBlob[i].z;
    float a = clamp((1.0 - d) / 0.6, 0.0, 1.0) * uBlob[i].w;  // exact [0,0.4,1]->[1,1,0]
    col = mix(col, uColor[i].rgb, a);                  // srcOver, same blob order
  }
  fragColor = vec4(col, 1.0);                          // opaque full-bleed base
}
```

`clamp((1.0 - d) / 0.6, 0, 1)` reproduces the current gradient stops exactly: `1`
for `d ≤ 0.4`, linear to `0` at `d = 1`, `0` beyond. The loop reproduces the
srcOver accumulation in the same blob order. Result is therefore pixel-identical to
the current painter.

### 2. Pure uniform assembly — `lib/Widgets/gradient/mesh_geometry.dart`

Add a pure, unit-testable function that produces the uniform buffer (no GPU, no
Flutter binding needed):

```dart
/// Packs the mesh's per-frame uniforms in the order mesh.frag declares them.
/// Returns 58 floats: uSize, uIdle, uCanvas, 6×uBlob(cx,cy,r,alpha), 6×uColor(rgb,_).
Float32List buildMeshUniforms(Mesh mesh, Color idle, Size size);
```

It calls `blobPlacement` for each of `kBlobs`, selects `mesh.a`/`mesh.b` via
`useA`, and writes floats using the new `Color` component API (`.r/.g/.b`, 0..1).
Blob alpha = `blob.opacity * mesh.opacity`; canvas alpha = `mesh.opacity`; idle
alpha = `1`. This is the only place the float order is defined.

### 3. Painter + widget lifecycle — `floating_gradient_background.dart`

**Program loading.** `ui.FragmentProgram` is immutable and reusable; load it once
behind a static cached future:

```dart
static Future<ui.FragmentProgram>? _programFuture;
// in initState: _programFuture ??= ui.FragmentProgram.fromAsset('shaders/mesh.frag');
// await it, then _shader = program.fragmentShader(); then repaint.
```

The widget holds one `ui.FragmentShader? _shader`, reuses it across frames (re-sets
uniforms each paint), and disposes it in `dispose()`.

**Painter.** `_MeshPainter` takes the `ui.FragmentShader?`. Keep `_bgPaint` for the
flat idle fill and add a **dedicated** `_meshPaint` for the shader draw (never share
one `Paint` between a `color` fill and a `shader` fill — a stale `.shader` left on the
paint would corrupt the next idle frame). The old `_blobPaints` list is removed.

```dart
final rect = Offset.zero & size;
final o = mesh.opacity;
if (shader == null || o <= 0) {
  canvas.drawRect(rect, _bgPaint..color = idleColor);    // flat idle (no shader), zero frames
  return;
}
final u = buildMeshUniforms(mesh, idleColor, size);
for (var k = 0; k < u.length; k++) shader.setFloat(k, u[k]);
canvas.drawRect(rect, _meshPaint..shader = shader);      // one full-screen pass
```

`shouldRepaint` stays `true` (it only repaints when the `_repaint` notifier fires,
which only happens while the ticker runs — unchanged).

### 4. pubspec.yaml

```yaml
flutter:
  shaders:
    - shaders/mesh.frag
```

### 5. Frame rate

`_minFrameInterval`: `1 / 30` → **`1 / 24`**. The 15s drift loop and multi-second
fades hide it; ~20% fewer frames for free. Keep it a named constant so it stays
tunable.

## Files changed

| File | Change |
|------|--------|
| `shaders/mesh.frag` | **new** — the shader above |
| `pubspec.yaml` | add `shaders:` entry |
| `lib/Widgets/gradient/mesh_geometry.dart` | add pure `buildMeshUniforms` |
| `lib/Widgets/floating_gradient_background.dart` | load program, hold/dispose `FragmentShader`, shader-based `paint`, `_minFrameInterval` → 1/24 |
| `test/widgets/gradient/mesh_uniforms_test.dart` | **new** — unit-test the packing |

## Testing strategy

- **`buildMeshUniforms` unit test (new).** Assert length 58 and exact float order /
  values for a known `Mesh` + `Size` (cross-checked against `blobPlacement`,
  `blob.opacity·o`, canvas `a = o`, idle `a = 1`, A/B selection). This locks the
  geometry, color selection, alpha math, and uniform ordering with no GPU.
- **Existing scheduling tests stay green, unchanged** —
  `floating_gradient_background_test.dart`: "idle schedules no frames" and "stops
  after fade-out". These test the ticker, not the painter internals.
- **Shader pixel output is not unit-testable.** Fragment shaders do not execute in
  headless `flutter test` (no GPU), so visual parity is verified by **running the
  app** before/after (generate a response on light, dark, and incognito modes and
  confirm the background is indistinguishable). This is called out so it is not
  silently skipped.

## Risks & mitigations

- **Web HTML renderer** does not support fragment shaders (Impeller on mobile and
  CanvasKit on web do). Out of scope unless the app ships the HTML renderer; Path B
  (atlas + half-res) remains the documented fallback if so.
- **Uniform layout / std140 padding.** `vec3` *arrays* pad each element to 16 bytes,
  which would desync `setFloat` indices — avoided by using `vec4` for `uColor`. If
  the compiled layout still inserts unexpected padding, the fix is local: adjust the
  index map in `buildMeshUniforms` only. The unit test plus the first on-device run
  surface any mismatch immediately (garbled output).
- **Program-load window.** While `FragmentProgram.fromAsset` resolves on first
  launch, the painter falls back to the flat `idleColor` rect — negligible, and idle
  is the common case. No flash of wrong content.

## Out of scope / future

- **Path B (atlas + half-res)** — fallback only, not implemented now.
- **Further fps reduction** (20fps) or **larger savings** — not needed; revisit only
  if profiling asks for it.

## Expected impact

Pixel-identical look and motion; **~8× → ~1× fill per frame**; **0** per-frame shader
allocations (was ~540/sec); **24fps** instead of 30. All while-generating only —
idle remains a single flat rect with zero scheduled frames.
