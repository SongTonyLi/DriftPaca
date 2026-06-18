import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Mutable per-frame values the painter reads. [phase] advances continuously;
/// [opacity] (0..1) fades the whole mesh in/out over the flat idle background.
class Mesh {
  double phase = 0;
  double opacity = 0; // 0 = hidden (flat idle bg), 1 = full mesh
  Color a = const Color(0xFF000000);
  Color b = const Color(0xFF000000);
  Color canvas = const Color(0xFF000000);
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
