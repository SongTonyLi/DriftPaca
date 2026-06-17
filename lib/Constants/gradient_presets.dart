import 'package:flutter/material.dart';

/// Two colors that define a floating-gradient background. They seed both the
/// animated mesh and the app's Material theme. Stored as ARGB ints in Hive
/// (see gradient_settings.dart) — always plain [Color], never MaterialColor.
@immutable
class GradientPair {
  final Color c1;
  final Color c2;
  const GradientPair(this.c1, this.c2);

  @override
  bool operator ==(Object other) =>
      other is GradientPair && other.c1 == c1 && other.c2 == c2;

  @override
  int get hashCode => Object.hash(c1, c2);
}

/// Six curated pairs. Index 0 is the default. Chosen to read well in all three
/// modes (normal/dark/incognito) after the per-mode transforms in mode_palette.
const List<GradientPair> kGradientPresets = [
  GradientPair(Color(0xFF4FB4FF), Color(0xFFFF73B3)), // sky blue · pink
  GradientPair(Color(0xFFFF5D8F), Color(0xFFFFA23A)), // rose · amber
  GradientPair(Color(0xFF7C5CFF), Color(0xFF49D6C8)), // violet · teal
  GradientPair(Color(0xFF34C759), Color(0xFFBEE36B)), // green · lime
  GradientPair(Color(0xFFFF8A3D), Color(0xFFFFD24C)), // orange · gold
  GradientPair(Color(0xFF5B7CFA), Color(0xFFB06CFF)), // indigo · orchid
];
