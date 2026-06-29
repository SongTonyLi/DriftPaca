import 'dart:io';

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

    // uB0..uB5 — (cx, cy, 1/(r·scale)², blob.opacity * opacity)
    for (var i = 0; i < kBlobs.length; i++) {
      final p = blobPlacement(kBlobs[i], mesh.phase, size);
      final radius = p.radius * kConvBlobScale;
      final base = 8 + i * 4;
      expect(u[base + 0], closeTo(p.center.dx, 1e-3));
      expect(u[base + 1], closeTo(p.center.dy, 1e-3));
      expect(u[base + 2], closeTo(1 / (radius * radius), 1e-9));
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

  test('buildMeshUniforms in welcome mode packs four breathing corner blobs', () {
    final mesh = Mesh()
      ..a = const Color(0xFF112233)
      ..b = const Color(0xFF445566)
      ..canvas = const Color(0xFF778899)
      ..phase = 0
      ..opacity = 1.0
      ..welcome = true;
    const idle = Color(0xFFFFFFFF);
    const size = Size(400, 800);

    final u = buildMeshUniforms(mesh, idle, size);
    expect(u.length, 56);

    // Four corners: TL(0,0) TR(400,0) BL(0,800) BR(400,800); slot base = 8 + i*4.
    expect(u[8], closeTo(0, 1e-3));
    expect(u[9], closeTo(0, 1e-3));
    expect(u[12], closeTo(400, 1e-3));
    expect(u[13], closeTo(0, 1e-3));
    expect(u[16], closeTo(0, 1e-3));
    expect(u[17], closeTo(800, 1e-3));
    expect(u[20], closeTo(400, 1e-3));
    expect(u[21], closeTo(800, 1e-3));
    // Corner blobs have positive inverse-radius/alpha; slots 4 and 5 are unused (alpha 0).
    expect(u[10], greaterThan(0.0));
    expect(u[10], lessThan(1.0));
    expect(u[11], closeTo(0.9, 1e-6));
    expect(u[27], 0.0);
    expect(u[31], 0.0);
  });

  test('mesh shader blob field stays branchless in the per-pixel hot path', () {
    final shader = File('shaders/mesh.frag').readAsStringSync();
    final blobFieldBody = RegExp(
      r'vec4 blobField\(vec2 p, vec4 b, vec4 c\) \{([\s\S]*?)\n\}',
    ).firstMatch(shader)!.group(1)!;

    expect(blobFieldBody, isNot(contains(RegExp(r'\bif\s*\('))));
    expect(blobFieldBody, contains('clamp(1.0 - d2 * b.z, 0.0, 1.0)'));
  });
}
