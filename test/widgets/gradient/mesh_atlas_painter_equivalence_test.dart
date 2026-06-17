import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Widgets/gradient/blob_sprite.dart';
import 'package:llamaseek/Widgets/gradient/mesh_atlas_painter.dart';
import 'package:llamaseek/Widgets/gradient/mesh_geometry.dart';

/// The analytic reference: the original per-frame RadialGradient renderer.
class _ReferencePainter extends CustomPainter {
  final Mesh mesh;
  _ReferencePainter(this.mesh);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = mesh.canvas);
    for (final blob in kBlobs) {
      final p = blobPlacement(blob, mesh.phase, size);
      final color = blob.useA ? mesh.a : mesh.b;
      final rect = Rect.fromCircle(center: p.center, radius: p.radius);
      final shader = RadialGradient(
        colors: [
          color.withValues(alpha: blob.opacity),
          color.withValues(alpha: blob.opacity),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(rect);
      canvas.drawCircle(p.center, p.radius, Paint()..shader = shader);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

Future<Uint8List> _render(CustomPainter painter, Size size) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  final img =
      recorder.endRecording().toImageSync(size.width.toInt(), size.height.toInt());
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  img.dispose();
  return bytes.buffer.asUint8List();
}

void main() {
  testWidgets('atlas renderer matches the analytic reference within tolerance',
      (tester) async {
    const size = Size(240, 480);
    final sprite = bakeBlobSprite(size: 512);
    addTearDown(sprite.dispose);
    const colors = [Color(0xFF4FB4FF), Color(0xFFFF73B3), Color(0xFFF4E9FF)];

    for (final phase in <double>[0.0, 1.3, 2.7, 4.0]) {
      final mesh = Mesh()
        ..phase = phase
        ..a = colors[0]
        ..b = colors[1]
        ..canvas = colors[2];

      late Uint8List ref;
      late Uint8List atlas;
      await tester.runAsync(() async {
        ref = await _render(_ReferencePainter(mesh), size);
        atlas =
            await _render(MeshAtlasPainter(mesh, sprite, ValueNotifier(0)), size);
      });

      expect(atlas.length, ref.length);
      var sumAbs = 0;
      var diffPixels = 0;
      for (var i = 0; i < ref.length; i += 4) {
        final d = (ref[i] - atlas[i]).abs() +
            (ref[i + 1] - atlas[i + 1]).abs() +
            (ref[i + 2] - atlas[i + 2]).abs() +
            (ref[i + 3] - atlas[i + 3]).abs();
        sumAbs += d;
        if (d > 48) diffPixels++;
      }
      final pixels = ref.length ~/ 4;
      final meanAbsPerChannel = sumAbs / ref.length;
      expect(meanAbsPerChannel, lessThan(8.0),
          reason: 'phase=$phase: mean per-channel diff too high');
      expect(diffPixels / pixels, lessThan(0.03),
          reason: 'phase=$phase: too many differing pixels');
    }
  });
}
