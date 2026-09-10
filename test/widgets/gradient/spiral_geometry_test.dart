import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Widgets/gradient/spiral_geometry.dart';

const _sizes = [
  Size(400, 800), // phone portrait
  Size(800, 400), // phone landscape
  Size(1024, 1024), // square
  Size(1600, 900), // desktop window
  Size(200, 240), // tiny (watch / split view)
];

double _farthestCorner(Offset c, Size s) => [
      c.distance,
      (c - Offset(s.width, 0)).distance,
      (c - Offset(0, s.height)).distance,
      (c - Offset(s.width, s.height)).distance,
    ].reduce(math.max);

void main() {
  test('the core floats around its anchor but stays near the middle of the canvas', () {
    for (final size in _sizes) {
      for (final welcome in [false, true]) {
        for (var phase = 0.0; phase < 40; phase += 0.37) {
          final p = spiralPlacement(phase, size, welcome: welcome);
          final anchor = Offset(kSpiralAnchor.dx * size.width, kSpiralAnchor.dy * size.height);
          expect((p.center - anchor).distance,
              lessThanOrEqualTo(kSpiralDriftAmt * size.shortestSide * math.sqrt2 + 1e-6),
              reason: 'core wandered too far on $size (welcome=$welcome)');
          expect(p.center.dx, inInclusiveRange(0.3 * size.width, 0.7 * size.width));
          expect(p.center.dy, inInclusiveRange(0.25 * size.height, 0.65 * size.height));
        }
      }
    }
  });

  test('the field reaches every corner wherever the core has floated to', () {
    // The arms thin out towards outerRadius rather than stopping, so the corners
    // must sit inside it or a screen would show a hard empty wedge.
    for (final size in _sizes) {
      for (final welcome in [false, true]) {
        for (var phase = 0.0; phase < 40; phase += 0.53) {
          final p = spiralPlacement(phase, size, welcome: welcome);
          expect(p.outerRadius, greaterThan(_farthestCorner(p.center, size)),
              reason: 'a corner of $size is outside the field');
        }
      }
    }
  });

  test('core arm pitch scales with the screen and gives several halftone dots per arm', () {
    for (final size in _sizes) {
      final p = spiralPlacement(0, size, welcome: false);
      expect(p.pitch, inInclusiveRange(kSpiralPitchMin, kSpiralPitchMax));
      // At least ~4 dot cells across one arm band, so an arm reads as a band of
      // dots and not a single wobbling line.
      expect(p.pitch / kHalftoneCell, greaterThanOrEqualTo(4.0), reason: 'too few dots per arm on $size');
      expect(p.coreRadius, greaterThan(0));
      expect(p.coreRadius, lessThan(p.outerRadius));
    }
    // Monotone in the short side (until the clamp).
    final small = spiralPlacement(0, const Size(300, 600), welcome: false).pitch;
    final large = spiralPlacement(0, const Size(500, 900), welcome: false).pitch;
    expect(large, greaterThan(small));
  });

  test('the generating field spins, streams and beads faster than the welcome intro', () {
    const size = Size(400, 800);
    const phase = 3.0;
    final gen = spiralPlacement(phase, size, welcome: false);
    final wel = spiralPlacement(phase, size, welcome: true);
    expect(gen.rotation, greaterThan(wel.rotation));
    expect(gen.flow, greaterThan(wel.flow));
    expect(gen.beadPhase, greaterThan(0));
    expect(wel.beadPhase, 0, reason: 'the intro has no token beads');
    // Both fields move at all, so a stuck picture cannot pass.
    for (final welcome in [false, true]) {
      final a = spiralPlacement(1.0, size, welcome: welcome);
      final b = spiralPlacement(1.5, size, welcome: welcome);
      expect(b.rotation, greaterThan(a.rotation));
      expect(b.flow, greaterThan(a.flow));
      expect(b.starTime, greaterThan(a.starTime));
    }
  });

  test('the look is quieter for the intro and over a light idle colour', () {
    final genDark = spiralLook(welcome: false, darkIdle: true);
    final genLight = spiralLook(welcome: false, darkIdle: false);
    final welDark = spiralLook(welcome: true, darkIdle: true);
    expect(genLight.intensity, lessThan(genDark.intensity), reason: 'text over a light idle needs calmer dots');
    expect(welDark.intensity, lessThan(genDark.intensity));
    expect(welDark.beadAmount, 0);
    expect(genDark.beadAmount, 1);
    expect(genDark.arms, greaterThanOrEqualTo(2));
    for (final look in [genDark, genLight, welDark]) {
      expect(look.intensity, inInclusiveRange(0, 1));
      expect(look.starStrength, inInclusiveRange(0, 1));
      expect(look.coreGlow, inInclusiveRange(0, 1));
    }
  });

  test('the field is dense in the middle and sparse at the edge', () {
    for (final welcome in [false, true]) {
      final look = spiralLook(welcome: welcome, darkIdle: true);
      // Arms open up with radius: at a phone's edge the gap is several times the
      // core gap, but never so wide that only one arm is left on screen.
      const size = Size(400, 800);
      final p = spiralPlacement(0, size, welcome: welcome);
      final edgeGap = p.pitch + look.growth * (size.height / 2);
      expect(look.growth, greaterThan(0));
      expect(edgeGap, greaterThan(2.5 * p.pitch), reason: 'edge should be clearly sparser (welcome=$welcome)');
      expect(edgeGap, lessThan(size.height / 2), reason: 'still more than one arm on a phone (welcome=$welcome)');
      // Dots thin out and arms narrow towards the edge.
      expect(look.edgeDensity, inInclusiveRange(0.2, 0.7));
      expect(look.armWidthEdge, lessThan(look.armWidthCore));
      expect(look.armWidthCore, inInclusiveRange(0.3, 0.9));
      expect(look.armWidthEdge, inInclusiveRange(0.2, 0.8));
    }
  });

  test('the highlight colour always contrasts with the idle background', () {
    const a = Color(0xFF4FB4FF), b = Color(0xFFFF73B3);
    final onDark = spiralHighlightColor(const Color(0xFF0A0B10), a, b);
    final onLight = spiralHighlightColor(const Color(0xFFF7F4FA), a, b);
    expect(onDark.computeLuminance(), greaterThan(0.5));
    expect(onLight.computeLuminance(), lessThan(0.25));
    // Same hue family as the mesh colours (their average), not an arbitrary grey.
    final mixHue = HSLColor.fromColor(Color.lerp(a, b, 0.5)!).hue;
    expect(HSLColor.fromColor(onDark).hue, closeTo(mixHue, 1.0));
    expect(HSLColor.fromColor(onLight).hue, closeTo(mixHue, 1.0));
  });
}
