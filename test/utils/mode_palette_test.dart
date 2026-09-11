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

bool _isLightMode(AppMode mode) => mode == AppMode.normal || mode == AppMode.incognitoLight;

void main() {
  const base = GradientPair(Color(0xFF4FB4FF), Color(0xFFFF73B3));

  test('scheme brightness follows the mode', () {
    expect(
      resolvePalette(base, AppMode.normal).scheme.brightness,
      Brightness.light,
    );
    expect(
      resolvePalette(base, AppMode.dark).scheme.brightness,
      Brightness.dark,
    );
    expect(
      resolvePalette(base, AppMode.incognitoLight).scheme.brightness,
      Brightness.light,
    );
    expect(
      resolvePalette(base, AppMode.incognitoDark).scheme.brightness,
      Brightness.dark,
    );
  });

  test('solid background follows the mode brightness', () {
    expect(_light(resolvePalette(base, AppMode.normal).idle), greaterThan(0.92));
    expect(_light(resolvePalette(base, AppMode.dark).idle), lessThan(0.12));
    expect(
      _light(resolvePalette(base, AppMode.incognitoLight).idle),
      greaterThan(0.85),
    );
    expect(
      _light(resolvePalette(base, AppMode.incognitoDark).idle),
      lessThan(0.12),
    );
  });

  test('normal background is a subtle wash of the selected colors', () {
    final mixSat = _sat(Color.lerp(base.c1, base.c2, 0.5)!);
    expect(_sat(resolvePalette(base, AppMode.normal).idle), lessThan(mixSat));
  });

  test('incognito uses a fixed muted indigo independent of user colors', () {
    const warm = GradientPair(Color(0xFFFF5500), Color(0xFFFFAA00));
    final a = HSLColor.fromColor(resolvePalette(base, AppMode.incognitoDark).idle);
    final b = HSLColor.fromColor(resolvePalette(warm, AppMode.incognitoDark).idle);

    expect(_hueDist(a.hue, b.hue), lessThan(1));
    expect(a.hue, inInclusiveRange(230, 285));
    expect(a.saturation, lessThan(0.50));
  });

  test('text stays legible on surface in every mode', () {
    for (final mode in AppMode.values) {
      final scheme = resolvePalette(base, mode).scheme;
      expect(
        _contrast(scheme.onSurface, scheme.surface),
        greaterThan(3.0),
        reason: 'low contrast in $mode',
      );
    }
  });

  test('solid background stays valid for pathological color inputs', () {
    const harsh = GradientPair(Color(0xFFFFFFFF), Color(0xFF000000));
    for (final mode in AppMode.values) {
      final background = resolvePalette(harsh, mode).idle;
      expect(_light(background), inInclusiveRange(0.0, 1.0));
      if (_isLightMode(mode)) {
        expect(_light(background), greaterThan(0.85));
      } else {
        expect(_light(background), lessThan(0.2));
      }
    }
  });
}
