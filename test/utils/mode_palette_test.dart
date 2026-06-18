import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Constants/gradient_presets.dart';
import 'package:llamaseek/Utils/mode_palette.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

double _sat(Color c) => HSLColor.fromColor(c).saturation;
double _light(Color c) => HSLColor.fromColor(c).lightness;

double _hueDist(double a, double b) {
  final d = (a - b).abs() % 360;
  return d > 180 ? 360 - d : d;
}

bool _isLightMode(AppMode m) =>
    m == AppMode.normal || m == AppMode.incognitoLight;

void main() {
  const base = GradientPair(Color(0xFF4FB4FF), Color(0xFFFF73B3));

  test('scheme brightness follows the mode', () {
    expect(resolvePalette(base, AppMode.normal).scheme.brightness, Brightness.light);
    expect(resolvePalette(base, AppMode.dark).scheme.brightness, Brightness.dark);
    expect(resolvePalette(base, AppMode.incognitoLight).scheme.brightness, Brightness.light);
    expect(resolvePalette(base, AppMode.incognitoDark).scheme.brightness, Brightness.dark);
  });

  test('dark canvas is darker than normal canvas', () {
    expect(_light(resolvePalette(base, AppMode.dark).canvas),
        lessThan(_light(resolvePalette(base, AppMode.normal).canvas)));
  });

  test('incognito-dark canvas is near-black', () {
    expect(_light(resolvePalette(base, AppMode.incognitoDark).canvas), lessThan(0.07));
  });

  test('normal idle is a near-white wash, lighter than the canvas', () {
    final p = resolvePalette(base, AppMode.normal);
    expect(_light(p.idle), greaterThan(0.92));
    expect(_light(p.idle), greaterThan(_light(p.canvas)));
  });

  test('idle background follows the mode brightness', () {
    expect(_light(resolvePalette(base, AppMode.dark).idle), lessThan(0.12));
    expect(_light(resolvePalette(base, AppMode.incognitoDark).idle), lessThan(0.12));
    expect(_light(resolvePalette(base, AppMode.incognitoLight).idle), greaterThan(0.92));
  });

  test('normal idle is a thinner (less saturated) wash of the mix', () {
    final mixSat = _sat(Color.lerp(base.c1, base.c2, 0.5)!);
    expect(_sat(resolvePalette(base, AppMode.normal).idle), lessThan(mixSat));
  });

  test('incognito uses a fixed muted indigo tint, independent of user colours', () {
    const warm = GradientPair(Color(0xFFFF5500), Color(0xFFFFAA00));
    final a = HSLColor.fromColor(resolvePalette(base, AppMode.incognitoDark).idle);
    final b = HSLColor.fromColor(resolvePalette(warm, AppMode.incognitoDark).idle);
    // Same incognito tint regardless of the user's gradient pair:
    expect(_hueDist(a.hue, b.hue), lessThan(1));
    // Muted indigo/violet:
    expect(a.hue, inInclusiveRange(230, 285));
    expect(a.saturation, lessThan(0.35));
  });

  test('incognito-dark mesh colors are heavily desaturated', () {
    final p = resolvePalette(base, AppMode.incognitoDark);
    expect(_sat(p.meshA), lessThan(0.35));
    expect(_sat(p.meshB), lessThan(0.35));
  });

  test('text stays legible on surface in every mode', () {
    for (final mode in AppMode.values) {
      final s = resolvePalette(base, mode).scheme;
      expect(_contrast(s.onSurface, s.surface), greaterThan(3.0),
          reason: 'low contrast in $mode');
    }
  });

  test('clamps survive pathological inputs (white + black)', () {
    const harsh = GradientPair(Color(0xFFFFFFFF), Color(0xFF000000));
    for (final mode in AppMode.values) {
      final p = resolvePalette(harsh, mode);
      expect(_light(p.canvas), inInclusiveRange(0.0, 1.0));
      if (_isLightMode(mode)) {
        expect(_light(p.canvas), greaterThan(0.85));
      } else {
        expect(_light(p.canvas), lessThan(0.2));
      }
    }
  });
}
