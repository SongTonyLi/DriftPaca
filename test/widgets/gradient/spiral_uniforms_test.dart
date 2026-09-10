import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Widgets/gradient/spiral_geometry.dart';

void main() {
  test('buildSpiralUniforms packs 40 floats in shader-declared order', () {
    final field = SpiralField()
      ..a = const Color(0xFF112233)
      ..b = const Color(0xFF445566)
      ..canvas = const Color(0xFF778899)
      ..phase = 1.234
      ..opacity = 0.6;
    const idle = Color(0xFFFFFFFF);
    const size = Size(400, 800);

    final u = buildSpiralUniforms(field, idle, size);
    expect(u.length, kSpiralUniformFloats);
    expect(u.length, 4 * kSpiralUniformOrder.length);

    final p = spiralPlacement(field.phase, size, welcome: false);
    final look = spiralLook(welcome: false, darkIdle: false);
    final star = spiralHighlightColor(idle, field.a, field.b);

    // uIdle — alpha forced to 1.0
    expect(u[0], closeTo(idle.r, 1e-6));
    expect(u[1], closeTo(idle.g, 1e-6));
    expect(u[2], closeTo(idle.b, 1e-6));
    expect(u[3], closeTo(1.0, 1e-6));
    // uCanvas — alpha = opacity
    expect(u[4], closeTo(field.canvas.r, 1e-6));
    expect(u[5], closeTo(field.canvas.g, 1e-6));
    expect(u[6], closeTo(field.canvas.b, 1e-6));
    expect(u[7], closeTo(0.6, 1e-6));
    // uColA / uColB
    expect(u[8], closeTo(field.a.r, 1e-6));
    expect(u[9], closeTo(field.a.g, 1e-6));
    expect(u[10], closeTo(field.a.b, 1e-6));
    expect(u[12], closeTo(field.b.r, 1e-6));
    expect(u[13], closeTo(field.b.g, 1e-6));
    expect(u[14], closeTo(field.b.b, 1e-6));
    // uStar — highlight colour, strength scaled by the fade
    expect(u[16], closeTo(star.r, 1e-6));
    expect(u[17], closeTo(star.g, 1e-6));
    expect(u[18], closeTo(star.b, 1e-6));
    expect(u[19], closeTo(look.starStrength * 0.6, 1e-6));
    // uSpiral — centre, pitch, rotation
    expect(u[20], closeTo(p.center.dx, 1e-3));
    expect(u[21], closeTo(p.center.dy, 1e-3));
    expect(u[22], closeTo(p.pitch, 1e-3));
    expect(u[23], closeTo(p.rotation, 1e-5));
    // uFlow — flow, bead phase, bead amount, arms
    expect(u[24], closeTo(p.flow, 1e-5));
    expect(u[25], closeTo(p.beadPhase, 1e-4));
    expect(u[26], closeTo(look.beadAmount, 1e-6));
    expect(u[27], closeTo(look.arms.toDouble(), 1e-6));
    // uField — core radius, outer radius, intensity, cell
    expect(u[28], closeTo(p.coreRadius, 1e-3));
    expect(u[29], closeTo(p.outerRadius, 1e-2));
    expect(u[30], closeTo(look.intensity, 1e-6));
    expect(u[31], closeTo(kHalftoneCell, 1e-6));
    // uTwinkle — star time, star drift, core glow, hue drift
    expect(u[32], closeTo(p.starTime, 1e-4));
    expect(u[33], closeTo(p.starDrift, 1e-3));
    expect(u[34], closeTo(look.coreGlow, 1e-6));
    expect(u[35], closeTo(p.hueDrift, 1e-5));
    // uShape — pitch growth, edge density, arm width at core / edge
    expect(u[36], closeTo(look.growth, 1e-6));
    expect(u[37], closeTo(look.edgeDensity, 1e-6));
    expect(u[38], closeTo(look.armWidthCore, 1e-6));
    expect(u[39], closeTo(look.armWidthEdge, 1e-6));
  });

  test('buildSpiralUniforms in welcome mode packs the quiet intro field', () {
    final field = SpiralField()
      ..a = const Color(0xFF112233)
      ..b = const Color(0xFF445566)
      ..canvas = const Color(0xFF778899)
      ..phase = 2.0
      ..opacity = 1.0
      ..welcome = true;
    const idle = Color(0xFF101014); // dark
    const size = Size(400, 800);

    final u = buildSpiralUniforms(field, idle, size);
    final p = spiralPlacement(field.phase, size, welcome: true);
    final look = spiralLook(welcome: true, darkIdle: true);

    expect(u[23], closeTo(p.rotation, 1e-6));
    expect(u[24], closeTo(p.flow, 1e-6));
    expect(u[25], 0.0, reason: 'no bead phase in the intro');
    expect(u[26], 0.0, reason: 'no token beads in the intro');
    expect(u[27], closeTo(look.arms.toDouble(), 1e-6));
    expect(u[30], closeTo(look.intensity, 1e-6));
    expect(u[19], closeTo(look.starStrength, 1e-6));
  });

  test('a hidden field packs zero alpha for canvas and stars', () {
    final field = SpiralField()..opacity = 0;
    final u = buildSpiralUniforms(field, const Color(0xFFFFFFFF), const Size(400, 800));
    expect(u[7], 0.0);
    expect(u[19], 0.0);
  });

  test('halftone_spiral.frag declares the uniforms in the packed order', () {
    final shader = File('shaders/halftone_spiral.frag').readAsStringSync();
    final declared = RegExp(r'^uniform\s+(\w+)\s+(\w+)\s*;', multiLine: true)
        .allMatches(shader)
        .map((m) => (type: m.group(1)!, name: m.group(2)!))
        .toList();
    expect(declared.map((d) => d.name).toList(), kSpiralUniformOrder,
        reason: 'the Dart packer and the shader must agree on the layout');
    expect(declared.map((d) => d.type).toSet(), {'vec4'},
        reason: 'every uniform is a vec4 so setFloat indices stay 4-aligned');
    expect(shader, contains('#include <flutter/runtime_effect.glsl>'));
    expect(shader, contains('FlutterFragCoord()'));
  });
}
