import 'package:flutter/material.dart';

/// Full-bleed background that paints one solid color without animation.
class StaticBackground extends StatelessWidget {
  final Color color;

  const StaticBackground({super.key, required this.color});

  @override
  Widget build(BuildContext context) => ColoredBox(color: color);
}
