import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Widgets/gradient/mesh_geometry.dart';

void main() {
  test('there are six blobs (unchanged from the original renderer)', () {
    expect(kBlobs.length, 6);
  });

  test('blobPlacement matches the analytic formula at a known phase', () {
    const size = Size(400, 800);
    const phase = 1.3;
    final blob = kBlobs.first;
    final p = blobPlacement(blob, phase, size);

    final expectedCx = (blob.baseX +
            blob.ampX * math.sin(phase * blob.freqX + blob.phaseX)) *
        size.width;
    final expectedCy = (blob.baseY +
            blob.ampY * math.cos(phase * blob.freqY + blob.phaseY)) *
        size.height;
    final expectedR = blob.radius *
        size.shortestSide *
        (1 + 0.10 * math.sin(phase * 0.6 + blob.phaseX));

    expect(p.center.dx, closeTo(expectedCx, 1e-9));
    expect(p.center.dy, closeTo(expectedCy, 1e-9));
    expect(p.radius, closeTo(expectedR, 1e-9));
  });

  test('radius stays positive across a full phase sweep', () {
    const size = Size(400, 800);
    for (final blob in kBlobs) {
      for (var phase = 0.0; phase < 20; phase += 0.13) {
        expect(blobPlacement(blob, phase, size).radius, greaterThan(0));
      }
    }
  });
}
