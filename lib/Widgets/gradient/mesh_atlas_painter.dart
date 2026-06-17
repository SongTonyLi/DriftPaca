import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:llamaseek/Widgets/gradient/mesh_geometry.dart';

/// Paints the mesh by drawing one cached [sprite] six times with a single
/// `drawRawAtlas` call — replacing six per-frame `RadialGradient` shader
/// compiles with one textured draw of a cached image. Per-blob position/scale
/// live in reused typed buffers (zero per-frame allocation); per-blob tint and
/// opacity ride in the `colors` buffer and combine with the white sprite via
/// `BlendMode.modulate`.
class MeshAtlasPainter extends CustomPainter {
  final Mesh mesh;
  final ui.Image sprite;

  final Paint _bgPaint = Paint();
  final Paint _atlasPaint = Paint()..filterQuality = FilterQuality.low;
  final Float32List _rst = Float32List(4 * kBlobs.length);
  final Float32List _rects = Float32List(4 * kBlobs.length);
  final Int32List _colors = Int32List(kBlobs.length);

  MeshAtlasPainter(this.mesh, this.sprite, Listenable repaint)
      : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, _bgPaint..color = mesh.canvas);

    final sw = sprite.width.toDouble();
    final sh = sprite.height.toDouble();
    for (var i = 0; i < kBlobs.length; i++) {
      final blob = kBlobs[i];
      final p = blobPlacement(blob, mesh.phase, size);
      final scale = (2 * p.radius) / sw; // sprite diameter -> 2 * radius

      // RSTransform raw layout per instance: [scos, ssin, tx, ty]. No rotation
      // (ssin = 0). Translate so the sprite's centre lands on p.center.
      final o = i * 4;
      _rst[o] = scale;
      _rst[o + 1] = 0.0;
      _rst[o + 2] = p.center.dx - scale * (sw / 2);
      _rst[o + 3] = p.center.dy - scale * (sh / 2);

      _rects[o] = 0.0;
      _rects[o + 1] = 0.0;
      _rects[o + 2] = sw;
      _rects[o + 3] = sh;

      final color = blob.useA ? mesh.a : mesh.b;
      _colors[i] = color.withValues(alpha: blob.opacity).toARGB32();
    }

    canvas.drawRawAtlas(
        sprite, _rst, _rects, _colors, BlendMode.modulate, null, _atlasPaint);
  }

  @override
  bool shouldRepaint(MeshAtlasPainter old) => true;
}
