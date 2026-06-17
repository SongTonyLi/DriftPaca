import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Bakes one reusable soft blob sprite: **white RGB** with an alpha falloff that
/// matches the original radial profile (solid through 40% of the radius, fading
/// to 0 at the edge). The sprite is **color-agnostic** — per-blob tint and
/// opacity are applied at draw time via `drawRawAtlas` + `BlendMode.modulate`,
/// so it is baked exactly once for the app's life.
///
/// Uses `Picture.toImageSync` so callers get a ready `ui.Image` synchronously.
ui.Image bakeBlobSprite({int size = 512}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final s = size.toDouble();
  final rect = Rect.fromLTWH(0, 0, s, s);
  final shader = const RadialGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
    stops: [0.0, 0.4, 1.0],
  ).createShader(rect);
  canvas.drawCircle(Offset(s / 2, s / 2), s / 2, Paint()..shader = shader);
  return recorder.endRecording().toImageSync(size, size);
}
