# Mesh Fragment Shader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repaint the floating-gradient background's six blobs in a single full-screen fragment-shader pass instead of six per-frame `RadialGradient` draws — pixel-identical look, ~8×→~1× fill, zero per-frame allocations, 24fps.

**Architecture:** The drift/colour/fade/scheduling logic stays in Dart unchanged. A new pure `buildMeshUniforms` packs the per-frame state into a `Float32List`; a new `shaders/mesh.frag` consumes it and composites the mesh in one pass; `_MeshPainter` sets the uniforms and issues one `drawRect(...shader)`. Idle (`opacity <= 0`) and the pre-load window stay on today's flat-`idleColor` path.

**Tech Stack:** Flutter (Dart), `dart:ui` `FragmentProgram`/`FragmentShader`, GLSL (`#version 460 core` + `flutter/runtime_effect.glsl`).

**Spec:** `docs/superpowers/specs/2026-06-18-floating-gradient-shader-design.md`

**Refinements vs spec (intentional):** (1) six individually-named `vec4` uniforms per group instead of `uBlob[6]`/`uColor[6]` arrays — avoids GLSL std140 array-padding ambiguity; (2) the `uSize` uniform is dropped — it is unused in the shader, and an unused uniform is stripped by the compiler, which would shift every `setFloat` index. Net uniform count is **56 floats**, not 58. Float order is unchanged otherwise.

**Uniform layout (single source of truth — used by Task 1 impl/test and Task 2 shader):**

| floats | uniform | value |
|--------|---------|-------|
| 0–3 | `uIdle` (vec4) | idle.r, idle.g, idle.b, **1.0** |
| 4–7 | `uCanvas` (vec4) | canvas.r, canvas.g, canvas.b, **o** (`mesh.opacity`) |
| 8–11 … 28–31 | `uB0`…`uB5` (vec4) | per blob `i`: cx, cy, r, **blob.opacity·o** |
| 32–35 … 52–55 | `uC0`…`uC5` (vec4) | per blob `i`: colour.r, colour.g, colour.b, 0.0 |

Blob `i` geometry base = `8 + i*4`; blob `i` colour base = `32 + i*4`. Colour = `kBlobs[i].useA ? mesh.a : mesh.b`.

---

## Task 1: Pure uniform packing (`buildMeshUniforms`)

**Files:**
- Create: `test/widgets/gradient/mesh_uniforms_test.dart`
- Modify: `lib/Widgets/gradient/mesh_geometry.dart` (add `dart:typed_data` import + the function)

- [ ] **Step 1: Write the failing test**

Create `test/widgets/gradient/mesh_uniforms_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Widgets/gradient/mesh_geometry.dart';

void main() {
  test('buildMeshUniforms packs 56 floats in shader-declared order', () {
    final mesh = Mesh()
      ..a = const Color(0xFF112233)
      ..b = const Color(0xFF445566)
      ..canvas = const Color(0xFF778899)
      ..phase = 1.234
      ..opacity = 0.6;
    const idle = Color(0xFFFFFFFF);
    const size = Size(400, 800);

    final u = buildMeshUniforms(mesh, idle, size);

    expect(u.length, 56);

    // uIdle — alpha forced to 1.0
    expect(u[0], closeTo(idle.r, 1e-6));
    expect(u[1], closeTo(idle.g, 1e-6));
    expect(u[2], closeTo(idle.b, 1e-6));
    expect(u[3], closeTo(1.0, 1e-6));

    // uCanvas — alpha = opacity
    expect(u[4], closeTo(mesh.canvas.r, 1e-6));
    expect(u[5], closeTo(mesh.canvas.g, 1e-6));
    expect(u[6], closeTo(mesh.canvas.b, 1e-6));
    expect(u[7], closeTo(0.6, 1e-6));

    // uB0..uB5 — (cx, cy, r, blob.opacity * opacity)
    for (var i = 0; i < kBlobs.length; i++) {
      final p = blobPlacement(kBlobs[i], mesh.phase, size);
      final base = 8 + i * 4;
      expect(u[base + 0], closeTo(p.center.dx, 1e-3));
      expect(u[base + 1], closeTo(p.center.dy, 1e-3));
      expect(u[base + 2], closeTo(p.radius, 1e-3));
      expect(u[base + 3], closeTo(kBlobs[i].opacity * mesh.opacity, 1e-6));
    }

    // uC0..uC5 — rgb of A or B per useA
    for (var i = 0; i < kBlobs.length; i++) {
      final c = kBlobs[i].useA ? mesh.a : mesh.b;
      final base = 32 + i * 4;
      expect(u[base + 0], closeTo(c.r, 1e-6));
      expect(u[base + 1], closeTo(c.g, 1e-6));
      expect(u[base + 2], closeTo(c.b, 1e-6));
    }
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/widgets/gradient/mesh_uniforms_test.dart`
Expected: FAIL — compile error, "The function 'buildMeshUniforms' isn't defined".

- [ ] **Step 3: Add the `dart:typed_data` import**

In `lib/Widgets/gradient/mesh_geometry.dart`, the current imports are:

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
```

Change to:

```dart
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
```

- [ ] **Step 4: Implement `buildMeshUniforms`**

Append to the end of `lib/Widgets/gradient/mesh_geometry.dart`:

```dart
/// Packs the mesh's per-frame state into the uniform buffer that shaders/mesh.frag
/// declares, in declaration order. Returns 56 floats:
///   uIdle(rgb,1) · uCanvas(rgb,o) · 6×(cx,cy,r,blob.opacity·o) · 6×(colour rgb,0).
/// Pure: no GPU or Flutter binding needed, so it is unit-testable.
Float32List buildMeshUniforms(Mesh mesh, Color idle, Size size) {
  final o = mesh.opacity;
  final u = Float32List(56);
  var k = 0;
  void w(double v) => u[k++] = v;

  w(idle.r); w(idle.g); w(idle.b); w(1.0);
  w(mesh.canvas.r); w(mesh.canvas.g); w(mesh.canvas.b); w(o);
  for (final blob in kBlobs) {
    final p = blobPlacement(blob, mesh.phase, size);
    w(p.center.dx); w(p.center.dy); w(p.radius); w(blob.opacity * o);
  }
  for (final blob in kBlobs) {
    final c = blob.useA ? mesh.a : mesh.b;
    w(c.r); w(c.g); w(c.b); w(0.0);
  }
  return u;
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/widgets/gradient/mesh_uniforms_test.dart`
Expected: PASS (1 test).

- [ ] **Step 6: Commit**

```bash
git add lib/Widgets/gradient/mesh_geometry.dart test/widgets/gradient/mesh_uniforms_test.dart
git commit -m "Add buildMeshUniforms packer for the mesh fragment shader"
```

---

## Task 2: Shader asset + pubspec registration

**Files:**
- Create: `shaders/mesh.frag`
- Modify: `pubspec.yaml`

- [ ] **Step 1: Create the shader**

Create `shaders/mesh.frag`:

```glsl
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
```

- [ ] **Step 2: Register the shader in pubspec**

In `pubspec.yaml`, the `flutter:` section currently contains:

```yaml
  assets:
    - assets/images/
    - assets/images/icons/
```

Add a `shaders:` block immediately after it (same indentation as `assets:`):

```yaml
  assets:
    - assets/images/
    - assets/images/icons/

  shaders:
    - shaders/mesh.frag
```

- [ ] **Step 3: Fetch packages / register the asset**

Run: `flutter pub get`
Expected: exit 0, ending with "Got dependencies!" (or "Resolving dependencies..." then success). This registers `shaders/mesh.frag` for compilation. (The GLSL itself is compiled at app build time — verified in Task 4's `flutter run`; `flutter analyze` does not check `.frag` files.)

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml shaders/mesh.frag
git commit -m "Add mesh.frag full-screen shader and register it in pubspec"
```

---

## Task 3: Render the mesh through the shader

**Files:**
- Modify: `lib/Widgets/floating_gradient_background.dart`

All edits are in this one file. `buildMeshUniforms`, `kBlobs`, and `blobPlacement` come from the already-imported `mesh_geometry.dart`.

- [ ] **Step 1: Add the `dart:ui` import**

Current top of file:

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:llamaseek/Utils/drift_speed.dart';
import 'package:llamaseek/Widgets/gradient/mesh_geometry.dart';
```

Change the first lines to:

```dart
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:llamaseek/Utils/drift_speed.dart';
import 'package:llamaseek/Widgets/gradient/mesh_geometry.dart';
```

- [ ] **Step 2: Drop the frame cap to ~24fps**

Replace:

```dart
  // Cap repaints to ~30fps; the drift is slow so painting every vsync wastes GPU.
  static const double _minFrameInterval = 1 / 30;
```

with:

```dart
  // Cap repaints to ~24fps; the drift is slow so painting every vsync wastes GPU.
  static const double _minFrameInterval = 1 / 24;
```

- [ ] **Step 3: Add shader state fields**

Replace:

```dart
  late final Ticker _ticker;
  final Mesh _mesh = Mesh();
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
```

with:

```dart
  late final Ticker _ticker;
  final Mesh _mesh = Mesh();
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);

  // The compiled program is immutable and reusable — cache it once for the app.
  static Future<ui.FragmentProgram>? _programFuture;
  ui.FragmentShader? _shader;
```

- [ ] **Step 4: Load the shader in initState + add `_loadShader`**

Replace:

```dart
  @override
  void initState() {
    super.initState();
    _mesh.a = widget.meshA;
    _mesh.b = widget.meshB;
    _mesh.canvas = widget.canvas;
    _ticker = createTicker(_onTick);
    // Only animate if we open mid-generation; otherwise stay flat/idle.
    if (widget.isGenerating) _ticker.start();
  }
```

with:

```dart
  @override
  void initState() {
    super.initState();
    _mesh.a = widget.meshA;
    _mesh.b = widget.meshB;
    _mesh.canvas = widget.canvas;
    _ticker = createTicker(_onTick);
    _loadShader();
    // Only animate if we open mid-generation; otherwise stay flat/idle.
    if (widget.isGenerating) _ticker.start();
  }

  Future<void> _loadShader() async {
    try {
      _programFuture ??= ui.FragmentProgram.fromAsset('shaders/mesh.frag');
      final program = await _programFuture!;
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
    } catch (_) {
      // Shader unavailable (headless test env / unsupported renderer): stay on
      // the flat idleColor fallback and allow a later mount to retry.
      _programFuture = null;
    }
  }
```

- [ ] **Step 5: Dispose the shader**

Replace:

```dart
  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }
```

with:

```dart
  @override
  void dispose() {
    _ticker.dispose();
    _shader?.dispose();
    _repaint.dispose();
    super.dispose();
  }
```

- [ ] **Step 6: Pass the shader into the painter**

Replace:

```dart
        painter: _MeshPainter(_mesh, widget.idleColor, _repaint),
```

with:

```dart
        painter: _MeshPainter(_mesh, widget.idleColor, _shader, _repaint),
```

- [ ] **Step 7: Replace `_MeshPainter` with the shader-based painter**

Replace the entire `_MeshPainter` class (from `class _MeshPainter extends CustomPainter {` through its closing `}`):

```dart
/// Paints a flat [idleColor] at rest; while [mesh.opacity] > 0 it draws the whole
/// six-blob mesh in a single full-screen [shader] pass (see shaders/mesh.frag).
/// At opacity 0 — and before the shader has loaded — it is just the flat colour,
/// so idle rendering is one rect and the host stops ticking.
class _MeshPainter extends CustomPainter {
  final Mesh mesh;
  final Color idleColor;
  final ui.FragmentShader? shader;
  final Paint _bgPaint = Paint();
  final Paint _meshPaint = Paint();

  _MeshPainter(this.mesh, this.idleColor, this.shader, Listenable repaint)
      : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final o = mesh.opacity;
    final fs = shader;
    if (fs == null || o <= 0) {
      canvas.drawRect(rect, _bgPaint..color = idleColor); // flat idle, no shader
      return;
    }
    final u = buildMeshUniforms(mesh, idleColor, size);
    for (var k = 0; k < u.length; k++) {
      fs.setFloat(k, u[k]);
    }
    canvas.drawRect(rect, _meshPaint..shader = fs);
  }

  @override
  bool shouldRepaint(_MeshPainter old) => true;
}
```

- [ ] **Step 8: Analyze**

Run: `flutter analyze lib/Widgets/floating_gradient_background.dart lib/Widgets/gradient/mesh_geometry.dart`
Expected: "No issues found!" (no unused imports/fields — `RadialGradient`/`_blobPaints` are gone).

- [ ] **Step 9: Run the existing scheduling tests**

Run: `flutter test test/widgets/floating_gradient_background_test.dart`
Expected: PASS (5 tests). The `try/catch` keeps the idle/"no frames" and "stops after fade-out" tests green even though `FragmentProgram.fromAsset` fails in the headless test env (it falls back to the flat idle rect and never throws to the binding).

- [ ] **Step 10: Commit**

```bash
git add lib/Widgets/floating_gradient_background.dart
git commit -m "Render the floating gradient mesh in one fragment-shader pass at 24fps"
```

---

## Task 4: Verify parity (full suite + on-device)

**Files:** none (verification gate).

- [ ] **Step 1: Run the full test suite**

Run: `flutter test`
Expected: ALL pass — `mesh_uniforms_test`, `floating_gradient_background_test`, `mesh_geometry_test`, and the rest of the suite unchanged.

- [ ] **Step 2: Build & run the app**

Run: `flutter run` (pick a connected device/simulator — iOS/Android/macOS use Impeller or Skia and support fragment shaders).
Expected: the app builds with no shader-compile error (a `.frag` syntax error would fail the build here).

- [ ] **Step 3: Visual parity checklist (compare against `main`)**

With the app running, send a message so the assistant generates, and confirm in each mode that the background is indistinguishable from before:

- [ ] Light mode: blobs fade in, drift independently, fade out after generation, settle to flat.
- [ ] Dark mode: same.
- [ ] Incognito mode: indigo-tinted mesh behaves the same.
- [ ] Idle (no generation): flat background, no animation (confirm no visible motion / no battery drain).

If anything differs from `main`, treat it as a bug in Task 1–3 (most likely a uniform-order mismatch between `buildMeshUniforms` and `mesh.frag`) and fix at the source, then re-run Steps 1–3.

- [ ] **Step 4 (optional): Confirm the win**

In Flutter DevTools' performance/GPU view while generating, confirm the raster cost is lower than `main` (one full-screen pass vs six gradient draws) and no per-frame shader allocations in the CPU timeline.

---

## Done

The background now repaints through one fragment-shader pass: pixel-identical look and motion, ~8×→~1× fill, no per-frame `createShader` allocations, 24fps; idle stays a single flat rect with zero scheduled frames.
