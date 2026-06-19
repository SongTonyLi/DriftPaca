import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Mutable per-frame values the painter reads. [phase] advances continuously;
/// [opacity] (0..1) fades the whole mesh in/out over the flat idle background.
class Mesh {
  double phase = 0;
  double opacity = 0; // 0 = hidden (flat idle bg), 1 = full mesh
  Color a = const Color(0xFF000000);
  Color b = const Color(0xFF000000);
  Color canvas = const Color(0xFF000000);
  bool welcome = false; // true during the welcome corner-breathe intro
}

/// Static description of one soft radial blob. Centers/amps are fractions of
/// size; [radius] is a fraction of the shortest side.
class Blob {
  final double baseX, baseY, ampX, ampY, freqX, freqY, phaseX, phaseY, radius, opacity;
  final bool useA;
  const Blob(this.baseX, this.baseY, this.ampX, this.ampY, this.freqX,
      this.freqY, this.phaseX, this.phaseY, this.radius, this.opacity, this.useA);
}

/// The six interleaved blobs (A: top-left, bottom-right, centre; B: the others)
/// so the two hues overlap and blend in the middle. Unchanged from the original
/// renderer.
const List<Blob> kBlobs = [
  Blob(0.22, 0.20, 0.16, 0.12, 1.0, 0.9, 0.0, 1.3, 0.95, 0.90, true),
  Blob(0.80, 0.24, 0.15, 0.14, 0.8, 1.1, 2.1, 0.4, 0.92, 0.90, false),
  Blob(0.24, 0.80, 0.14, 0.16, 1.2, 0.7, 4.0, 2.6, 0.95, 0.90, false),
  Blob(0.80, 0.82, 0.16, 0.13, 0.9, 1.0, 1.2, 3.4, 0.90, 0.90, true),
  Blob(0.50, 0.46, 0.22, 0.18, 0.7, 0.8, 3.0, 5.0, 0.78, 0.75, true),
  Blob(0.46, 0.56, 0.20, 0.22, 1.1, 0.9, 5.2, 1.7, 0.76, 0.75, false),
];

/// Conversation mesh blobs are scaled up so they overlap into a near-full field,
/// leaving only thin dotted seams between them.
const double kConvBlobScale = 1.05;

/// Welcome intro: four breathing corner blobs (radius as a fraction of the short
/// side), independent of the drifting conversation mesh.
const double kWelcomeCornerSize = 0.55;
const double kWelcomeBreatheAmt = 0.16;
const double kWelcomeBreatheSpeed = 1.6;

/// Where a blob sits this frame: on-screen [center] and [radius] in pixels.
class BlobPlacement {
  final Offset center;
  final double radius;
  const BlobPlacement(this.center, this.radius);
}

/// Computes a blob's centre and radius for [phase] over a canvas of [size].
/// Identical math to the original `_MeshPainter`.
BlobPlacement blobPlacement(Blob blob, double phase, Size size) {
  final short = size.shortestSide;
  final cx = (blob.baseX + blob.ampX * math.sin(phase * blob.freqX + blob.phaseX)) *
      size.width;
  final cy = (blob.baseY + blob.ampY * math.cos(phase * blob.freqY + blob.phaseY)) *
      size.height;
  final r = blob.radius * short * (1 + 0.10 * math.sin(phase * 0.6 + blob.phaseX));
  return BlobPlacement(Offset(cx, cy), r);
}

/// Packs the mesh's per-frame state into the uniform buffer that shaders/mesh.frag
/// declares, in declaration order. Returns 56 floats:
///   uIdle(rgb,1) · uCanvas(rgb,o) · 6×(cx,cy,r,alpha) · 6×(colour rgb,0).
/// The active mode decides the blobs: the welcome intro breathes four corner
/// blobs; otherwise the six drifting mesh blobs (scaled up so they overlap into a
/// near-full field with only thin dotted seams). Pure — unit-testable.
Float32List buildMeshUniforms(Mesh mesh, Color idle, Size size) {
  final o = mesh.opacity;
  final u = Float32List(56);
  var k = 0;
  void w(double v) => u[k++] = v;

  w(idle.r); w(idle.g); w(idle.b); w(1.0);
  w(mesh.canvas.r); w(mesh.canvas.g); w(mesh.canvas.b); w(o);

  final blobs = <(Offset, double, Color, double)>[]; // center, radius, colour, alpha
  if (mesh.welcome) {
    final short = size.shortestSide;
    final corners = <Offset>[
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ];
    for (var i = 0; i < 4; i++) {
      final breathe = 1 +
          kWelcomeBreatheAmt *
              math.sin(mesh.phase * kWelcomeBreatheSpeed + i * 1.7);
      blobs.add((
        corners[i],
        kWelcomeCornerSize * short * breathe,
        (i == 0 || i == 3) ? mesh.a : mesh.b,
        0.9 * o,
      ));
    }
  } else {
    for (final blob in kBlobs) {
      final p = blobPlacement(blob, mesh.phase, size);
      blobs.add((
        p.center,
        p.radius * kConvBlobScale,
        blob.useA ? mesh.a : mesh.b,
        blob.opacity * o,
      ));
    }
  }

  for (var i = 0; i < 6; i++) {
    if (i < blobs.length) {
      final b = blobs[i];
      w(b.$1.dx); w(b.$1.dy); w(b.$2); w(b.$4);
    } else {
      w(0); w(0); w(1); w(0); // unused slot: radius 1 avoids /0, alpha 0 = no draw
    }
  }
  for (var i = 0; i < 6; i++) {
    if (i < blobs.length) {
      final c = blobs[i].$3;
      w(c.r); w(c.g); w(c.b); w(0.0);
    } else {
      w(0); w(0); w(0); w(0);
    }
  }
  return u;
}
