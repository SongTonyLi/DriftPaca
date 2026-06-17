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

void main() {
  const base = GradientPair(Color(0xFF4FB4FF), Color(0xFFFF73B3));

  test('normal scheme is light, dark/incognito are dark', () {
    expect(resolvePalette(base, AppMode.normal).scheme.brightness, Brightness.light);
    expect(resolvePalette(base, AppMode.dark).scheme.brightness, Brightness.dark);
    expect(resolvePalette(base, AppMode.incognito).scheme.brightness, Brightness.dark);
  });

  test('dark canvas is darker than normal canvas', () {
    expect(_light(resolvePalette(base, AppMode.dark).canvas),
        lessThan(_light(resolvePalette(base, AppMode.normal).canvas)));
  });

  test('incognito canvas is near-black', () {
    expect(_light(resolvePalette(base, AppMode.incognito).canvas), lessThan(0.07));
  });

  test('incognito mesh colors are heavily desaturated', () {
    final p = resolvePalette(base, AppMode.incognito);
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
      if (mode == AppMode.normal) {
        expect(_light(p.canvas), greaterThan(0.85));
      } else {
        expect(_light(p.canvas), lessThan(0.2));
      }
    }
  });
}
