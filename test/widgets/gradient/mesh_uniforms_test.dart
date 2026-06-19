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
