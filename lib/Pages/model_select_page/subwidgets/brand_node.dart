import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// A single provider logo on the wheel: the SVG mark on a faint frosted chip,
/// scaled and glowing by how close it is to the top notch ([prominence]).
///
/// [prominence] runs 0 (far / at the bottom of the ring) → 1 (docked at the
/// notch). It drives the chip opacity, the accent glow, and a docked accent
/// ring so the selected brand reads as "lit up".
class BrandNode extends StatelessWidget {
  final String asset;
  final Color accent;
  final bool tinted;
  final double size;
  final double prominence;

  const BrandNode({
    super.key,
    required this.asset,
    required this.accent,
    required this.size,
    this.tinted = false,
    this.prominence = 0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = prominence.clamp(0.0, 1.0);
    final docked = p > 0.85;

    final chip = cs.surface.withValues(alpha: lerpDouble(0.42, 0.9, p)!);
    final ring = docked
        ? accent.withValues(alpha: 0.9)
        : cs.outline.withValues(alpha: 0.14);
    final logoPad = size * 0.24;

    // Fallback marks are flat silhouettes — tint them to the foreground so they
    // read in every mode. Real brand logos keep their own colours.
    final tint = tinted ? cs.onSurface.withValues(alpha: 0.72) : null;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: chip,
        border: Border.all(color: ring, width: docked ? 1.6 : 0.8),
        boxShadow: p <= 0.02
            ? null
            : [
                BoxShadow(
                  color: accent.withValues(alpha: 0.45 * p),
                  blurRadius: 24 * p,
                  spreadRadius: 0.5 * p,
                ),
              ],
      ),
      child: Padding(
        padding: EdgeInsets.all(logoPad),
        child: SvgPicture.asset(
          asset,
          fit: BoxFit.contain,
          colorFilter:
              tint == null ? null : ColorFilter.mode(tint, BlendMode.srcIn),
        ),
      ),
    );
  }
}
