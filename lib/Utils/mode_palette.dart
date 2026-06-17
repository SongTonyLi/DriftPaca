import 'package:flutter/material.dart';
import 'package:llamaseek/Constants/gradient_presets.dart';

enum AppMode { normal, dark, incognito }

/// Per-mode result: the two mesh colors, the canvas behind them, and a
/// Material scheme seeded from both colors.
@immutable
class ResolvedPalette {
  final Color meshA;
  final Color meshB;
  final Color canvas;
  final ColorScheme scheme;
  const ResolvedPalette({
    required this.meshA,
    required this.meshB,
    required this.canvas,
    required this.scheme,
  });
}

HSLColor _hsl(Color c) => HSLColor.fromColor(c);

/// Multiply saturation/lightness, clamped to [0,1].
Color _scale(Color c, {double s = 1.0, double l = 1.0}) {
  final h = _hsl(c);
  return HSLColor.fromAHSL(
    h.alpha,
    h.hue,
    (h.saturation * s).clamp(0.0, 1.0),
    (h.lightness * l).clamp(0.0, 1.0),
  ).toColor();
}

/// Force lightness into [min,max] (keeps hue/saturation).
Color _clampL(Color c, double min, double max) {
  final h = _hsl(c);
  return h.withLightness(h.lightness.clamp(min, max)).toColor();
}

Color _setL(Color c, double l) => _hsl(c).withLightness(l.clamp(0.0, 1.0)).toColor();

ResolvedPalette resolvePalette(GradientPair base, AppMode mode) {
  switch (mode) {
    case AppMode.normal:
      final a = _clampL(base.c1, 0.45, 0.72);
      final b = _clampL(base.c2, 0.45, 0.72);
      final canvas = _setL(base.c1, 0.96);
      return ResolvedPalette(
        meshA: a, meshB: b, canvas: canvas,
        scheme: _scheme(a, b, Brightness.light),
      );
    case AppMode.dark:
      final a = _clampL(_scale(base.c1, s: 0.85, l: 0.45), 0.18, 0.40);
      final b = _clampL(_scale(base.c2, s: 0.85, l: 0.45), 0.18, 0.40);
      final canvas = _setL(base.c1, 0.08);
      return ResolvedPalette(
        meshA: a, meshB: b, canvas: canvas,
        scheme: _scheme(a, b, Brightness.dark),
      );
    case AppMode.incognito:
      final a = _clampL(_scale(base.c1, s: 0.22, l: 0.32), 0.16, 0.34);
      final b = _clampL(_scale(base.c2, s: 0.22, l: 0.32), 0.16, 0.34);
      final canvas = _setL(base.c1, 0.04);
      // One vivid accent keeps buttons/outgoing bubbles readable.
      final accent = _clampL(_scale(base.c1, s: 0.9), 0.55, 0.70);
      final scheme = _scheme(accent, b, Brightness.dark).copyWith(surface: canvas);
      return ResolvedPalette(
        meshA: a, meshB: b, canvas: canvas, scheme: scheme,
      );
  }
}

/// Seed a scheme so BOTH colors contribute: primary family from [primarySeed],
/// secondary/tertiary family from [secondarySeed].
ColorScheme _scheme(Color primarySeed, Color secondarySeed, Brightness brightness) {
  final primary = ColorScheme.fromSeed(
    seedColor: primarySeed,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.neutral,
  );
  final secondary = ColorScheme.fromSeed(
    seedColor: secondarySeed,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.neutral,
  );
  return primary.copyWith(
    secondary: secondary.primary,
    onSecondary: secondary.onPrimary,
    secondaryContainer: secondary.primaryContainer,
    onSecondaryContainer: secondary.onPrimaryContainer,
    tertiary: secondary.tertiary,
    onTertiary: secondary.onTertiary,
  );
}
