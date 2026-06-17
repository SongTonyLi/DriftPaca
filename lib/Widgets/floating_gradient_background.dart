import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:llamaseek/Utils/drift_speed.dart';
import 'package:llamaseek/Widgets/gradient/mesh_geometry.dart';

/// Full-bleed animated mesh of soft radial-gradient blobs in [meshA]/[meshB]
/// over [canvas]. Drift advances via an accumulated phase whose rate eases up
/// while [isGenerating] is true, so speed changes never jump. Place at the
/// bottom of a Stack behind app content.
class FloatingGradientBackground extends StatefulWidget {
  final Color meshA;
  final Color meshB;
  final Color canvas;
  final bool isGenerating;

  const FloatingGradientBackground({
    super.key,
    required this.meshA,
    required this.meshB,
    required this.canvas,
    required this.isGenerating,
  });

  @override
  State<FloatingGradientBackground> createState() =>
      _FloatingGradientBackgroundState();
}

class _FloatingGradientBackgroundState extends State<FloatingGradientBackground>
    with SingleTickerProviderStateMixin {
  static const double _restLoopSeconds = 15.0; // Medium motion
  static const double _colorFadeSeconds = 0.4; // matches AnimatedTheme
  static final double _baseRate = 2 * math.pi / _restLoopSeconds;
  // Cap repaints to ~30fps. The drift is slow, so painting every vsync (up to
  // 120fps) wastes GPU/battery for no visible benefit.
  static const double _minFrameInterval = 1 / 30;

  late final Ticker _ticker;
  final Mesh _mesh = Mesh();
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);

  Duration _last = Duration.zero;
  double _speed = kRestDriftSpeed;
  double _colorT = 1.0;
  late Color _fromA, _fromB, _fromCanvas;

  @override
  void initState() {
    super.initState();
    _mesh.a = _fromA = widget.meshA;
    _mesh.b = _fromB = widget.meshB;
    _mesh.canvas = _fromCanvas = widget.canvas;
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(FloatingGradientBackground old) {
    super.didUpdateWidget(old);
    if (old.meshA != widget.meshA ||
        old.meshB != widget.meshB ||
        old.canvas != widget.canvas) {
      _fromA = _mesh.a;
      _fromB = _mesh.b;
      _fromCanvas = _mesh.canvas;
      _colorT = 0.0; // restart the color cross-fade; phase is untouched
    }
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    // Throttle to ~30fps: skip sub-interval ticks to save battery. _last only
    // advances on a real frame, so dt accumulates and phase stays continuous.
    if (dt < _minFrameInterval) return;
    _last = elapsed;

    // isGenerating is read live each tick (not handled in didUpdateWidget, like
    // phase) so the speed target tracks generation state immediately.
    _speed = easeDriftSpeed(
        _speed, targetDriftSpeed(isGenerating: widget.isGenerating), dt);
    _mesh.phase += dt * _baseRate * _speed;

    if (_colorT < 1.0) {
      _colorT = math.min(1.0, _colorT + dt / _colorFadeSeconds);
      final e = Curves.easeInOutCubic.transform(_colorT);
      _mesh.a = Color.lerp(_fromA, widget.meshA, e)!;
      _mesh.b = Color.lerp(_fromB, widget.meshB, e)!;
      _mesh.canvas = Color.lerp(_fromCanvas, widget.canvas, e)!;
    }
    _repaint.value++; // repaint only the painter, no widget rebuild
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        isComplex: true,
        willChange: true,
        painter: _MeshPainter(_mesh, _repaint),
      ),
    );
  }
}

class _MeshPainter extends CustomPainter {
  final Mesh mesh;
  // Hoisted out of paint() so the always-on animation doesn't allocate a Paint
  // per blob every frame. Shaders still rebuild per frame (the blobs move), but
  // the Paint objects are reused.
  final Paint _bgPaint = Paint();
  final List<Paint> _blobPaints = List.generate(kBlobs.length, (_) => Paint());

  _MeshPainter(this.mesh, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, _bgPaint..color = mesh.canvas);
    for (var i = 0; i < kBlobs.length; i++) {
      final blob = kBlobs[i];
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
      canvas.drawCircle(p.center, p.radius, _blobPaints[i]..shader = shader);
    }
  }

  @override
  bool shouldRepaint(_MeshPainter oldDelegate) => true;
}
