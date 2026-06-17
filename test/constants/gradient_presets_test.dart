import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Constants/gradient_presets.dart';

void main() {
  group('GradientPair', () {
    test('holds two colors', () {
      const p = GradientPair(Color(0xFF112233), Color(0xFF445566));
      expect(p.c1, const Color(0xFF112233));
      expect(p.c2, const Color(0xFF445566));
    });

    test('equality is value-based', () {
      expect(const GradientPair(Color(0xFFAA0000), Color(0xFF00AA00)),
          const GradientPair(Color(0xFFAA0000), Color(0xFF00AA00)));
    });
  });

  group('kGradientPresets', () {
    test('provides exactly six pairs', () {
      expect(kGradientPresets.length, 6);
    });

    test('every color is a plain Color (not a MaterialColor)', () {
      for (final p in kGradientPresets) {
        expect(p.c1.runtimeType, Color);
        expect(p.c2.runtimeType, Color);
      }
    });

    test('has a usable default at index 0', () {
      expect(kGradientPresets.first.c1, isNot(kGradientPresets.first.c2));
    });
  });
}
