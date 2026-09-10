# Halftone token spiral background — replacing the floating blob mesh

- **Date:** 2026-09-10
- **Status:** Implemented
- **Component:** `lib/Widgets/floating_gradient_background.dart`,
  `lib/Widgets/gradient/spiral_geometry.dart`, `shaders/halftone_spiral.frag`

## Context

The full-screen background drawn while the assistant generates was a drifting
field of six soft radial-gradient blobs in the user's two palette colours,
frosted by a 38 px backdrop blur (see
`2026-06-18-floating-gradient-shader-design.md`). The request: make that
full-screen animation a **floating halftone spiral** that showcases tokens being
generated, with a more AI / futuristic, **starry** feel.

Everything around the picture is kept:

- the widget name and constructor (`FloatingGradientBackground(meshA, meshB,
  canvas, idleColor, isGenerating, isWelcome)`), so `main_page.dart` and
  `model_select_page.dart` are untouched and `mode_palette.dart` still supplies
  the colours;
- the ticker contract: a flat `idleColor` with **zero frames at idle**, a ~2 s
  fade in when generation starts, a ~3 s fade out when it ends, the ~24 fps
  repaint cap, the one-shot welcome intro, the "fields only swap while
  invisible" dissolve, and the reduced-motion path (static end state, no
  frames);
- the single full-screen fragment-shader pass and pure Dart uniform packing
  (no per-frame allocations beyond one `Float32List`).

## The picture

One fragment pass, `shaders/halftone_spiral.frag`, per pixel:

1. **Halftone screen.** A ~22° rotated grid of 11 px cells. The spiral field is
   sampled at the *centre* of the pixel's cell, so each cell is one clean disc
   whose radius is `sqrt(coverage)` — a true halftone, not a per-pixel dither.
2. **Spiral field.** Archimedean, `arms` arms, radial pitch `≈0.17 × short side`
   (clamped 44–132 px so an arm is always several dots wide). The crossing
   coordinate `t = r/pitch − arms·θ/2π − flow` is integral on an arm centre;
   `flow` grows with time so every arm slides **outward from the core** — the
   dots are tokens being emitted. A hollow, glowing core sits at the origin; the
   field thins out towards `0.66 × diagonal`, which covers every corner wherever
   the core has floated to.
3. **Token beads.** While generating, a sine packet runs outward along each arm
   (offset per arm), so the dots swell and dim in travelling pulses and the peaks
   flash toward the highlight colour. The welcome intro has no beads.
4. **Colour.** The two palette hues swirl along the arms (`sin(θ + r/pitch·0.35
   + drift)`); the core glow is their average.
5. **Stars.** Two hashed-grid layers (46 px sparse, 27 px dense), one star per
   gated cell with a 1 px core, soft halo, individual twinkle rhythm, and a
   four-point flare on the brightest few. The layers drift at different rates for
   parallax. Each star stays inside its own cell, so no neighbour lookups.

The **highlight / star colour** is derived in Dart from the palette: the two
hues' average hue, pale (L 0.88) over a dark idle and deep (L 0.36) over a light
one, so stars always read against the base.

## Motion

`SpiralField.phase` drives everything (as `Mesh.phase` did): drift radians while
generating (`2π / 15 s`, ×1.4 during generation via `drift_speed.dart`), real
seconds during the welcome intro. Per-field rates live in `kGeneratingMotion` /
`kWelcomeMotion`: spin, outward flow, bead speed, hue drift, star time, star
parallax, and the core's slow Lissajous float (±0.06 × short side around a point
a little above centre).

| | generating | welcome intro |
|---|---|---|
| arms | 3 | 2 |
| spin | ~30 s per turn | ~50 s per turn |
| outward flow | ~0.5 pitch/s | ~0.1 pitch/s |
| token beads | on (~1 Hz packets) | off |
| dot intensity | 0.90 dark / 0.62 light | 0.55 dark / 0.40 light |
| stars | 0.85 dark / 0.75 light | 1.0 dark / 0.85 light |

## Legibility

The old frosted-glass `BackdropFilter` is gone: crisp dots and 1 px stars *are*
the effect and a 38 px blur would smear them back into a wash. Instead the field
is held back where text sits on it: `spiralLook` lowers the dot intensity over a
light idle (0.62), the core glow is capped at 55 % of its colour, and the
brightest star components are small. Removing the blur pass also removes the
most expensive full-screen layer the old design had.

## Files

| File | Change |
|---|---|
| `shaders/halftone_spiral.frag` | **new** — replaces `shaders/mesh.frag` |
| `lib/Widgets/gradient/spiral_geometry.dart` | **new** — replaces `mesh_geometry.dart`: `SpiralField`, placement, look, highlight colour, `buildSpiralUniforms` (9 × vec4 = 36 floats), `kSpiralUniformOrder` |
| `lib/Widgets/floating_gradient_background.dart` | same lifecycle; paints the spiral, no glass layer |
| `lib/preview_spiral.dart` | **new** — isolated preview harness (`flutter run -t lib/preview_spiral.dart`), with query-parameter presets on the web for screenshots |
| `test/widgets/gradient/spiral_geometry_test.dart` | **new** — core stays central, field covers every corner, pitch gives ≥4 dots per arm, fields move, look and highlight contrast |
| `test/widgets/gradient/spiral_uniforms_test.dart` | **new** — packing order, welcome/hidden packing, and the shader source declares exactly `kSpiralUniformOrder` as vec4s |
| `test/widgets/floating_gradient_background_test.dart` | renamed accessor only; the scheduling tests are unchanged and still pass |
| `pubspec.yaml` | shader asset entry |

## Verification

- `flutter test test/widgets/gradient test/widgets/floating_gradient_background_test.dart` — 19 tests pass.
- Fragment shaders do not execute in headless `flutter test`, so the picture was
  checked by building the preview harness for the web and screenshotting it in
  headless Chromium in light, dark and incognito modes (see
  `docs/screenshots/halftone_spiral_dark.png` and `halftone_spiral_light.png`, taken
  with `lib/preview_spiral.dart` at `?mode=…&generating=1&controls=0`).
