import 'package:flutter/material.dart';
import 'package:llamaseek/Constants/gradient_presets.dart';

enum AppMode { normal, dark, incognitoLight, incognitoDark }

/// Solid background color and Material scheme for an app mode.
@immutable
class ResolvedPalette {
  final Color idle;
  final ColorScheme scheme;

  const ResolvedPalette({required this.idle, required this.scheme});
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

/// A thin, subtle background wash derived from the selected color pair.
Color _idleTint(Color base, double lightness, {double satScale = 0.45}) {
  final h = _hsl(base);
  return HSLColor.fromAHSL(
    1.0,
    h.hue,
    (h.saturation * satScale).clamp(0.0, 1.0),
    lightness,
  ).toColor();
}

/// Muted indigo/violet used for private-browsing modes.
Color _incognitoTint(double lightness) => HSLColor.fromAHSL(1.0, 258, 0.42, lightness).toColor();

Color _incognitoSchemeSeed(double hue, double lightness) => HSLColor.fromAHSL(1.0, hue, 0.45, lightness).toColor();

ResolvedPalette resolvePalette(GradientPair base, AppMode mode) {
  final mix = Color.lerp(base.c1, base.c2, 0.5)!;
  switch (mode) {
    case AppMode.normal:
      final primary = _clampL(base.c1, 0.45, 0.72);
      final secondary = _clampL(base.c2, 0.45, 0.72);
      return ResolvedPalette(
        idle: _idleTint(mix, 0.96),
        scheme: _scheme(primary, secondary, Brightness.light),
      );
    case AppMode.dark:
      final primary = _clampL(_scale(base.c1, s: 0.85, l: 0.45), 0.18, 0.40);
      final secondary = _clampL(_scale(base.c2, s: 0.85, l: 0.45), 0.18, 0.40);
      return ResolvedPalette(
        idle: _idleTint(mix, 0.06),
        scheme: _scheme(primary, secondary, Brightness.dark),
      );
    case AppMode.incognitoLight:
      final secondary = _incognitoSchemeSeed(274, 0.66);
      final surface = _incognitoTint(0.86);
      final accent = _clampL(_scale(base.c1, s: 0.9), 0.40, 0.55);
      return ResolvedPalette(
        idle: _incognitoTint(0.90),
        scheme: _scheme(accent, secondary, Brightness.light).copyWith(surface: surface),
      );
    case AppMode.incognitoDark:
      final secondary = _incognitoSchemeSeed(274, 0.34);
      final surface = _incognitoTint(0.07);
      final accent = _clampL(_scale(base.c1, s: 0.9), 0.55, 0.70);
      return ResolvedPalette(
        idle: _incognitoTint(0.10),
        scheme: _scheme(accent, secondary, Brightness.dark).copyWith(surface: surface),
      );
  }
}

/// Seed a scheme so both selected colors contribute.
ColorScheme _scheme(
  Color primarySeed,
  Color secondarySeed,
  Brightness brightness,
) {
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
