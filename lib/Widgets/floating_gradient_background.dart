import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:llamaseek/Utils/drift_speed.dart';

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

  late final Ticker _ticker;
  final _Mesh _mesh = _Mesh();
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
    _last = elapsed;
    if (dt <= 0) return;

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

/// Mutable values the painter reads each frame.
class _Mesh {
  double phase = 0;
  Color a = const Color(0xFF000000);
  Color b = const Color(0xFF000000);
  Color canvas = const Color(0xFF000000);
}

class _Blob {
  final double baseX, baseY, ampX, ampY, freqX, freqY, phaseX, phaseY, radius, opacity;
  final bool useA;
  const _Blob(this.baseX, this.baseY, this.ampX, this.ampY, this.freqX,
      this.freqY, this.phaseX, this.phaseY, this.radius, this.opacity, this.useA);
}

// Centers/amps are fractions of size; radius is a fraction of the shortest side.
const List<_Blob> _blobs = [
  _Blob(0.18, 0.12, 0.10, 0.08, 1.0, 0.9, 0.0, 1.3, 0.62, 0.95, true),
  _Blob(0.82, 0.78, 0.12, 0.10, 0.8, 1.1, 2.1, 0.4, 0.70, 0.95, false),
  _Blob(0.80, 0.10, 0.09, 0.07, 1.2, 0.7, 4.0, 2.6, 0.48, 0.85, true),
  _Blob(0.12, 0.82, 0.08, 0.09, 0.9, 1.0, 1.2, 3.4, 0.54, 0.85, false),
  _Blob(0.50, 0.45, 0.14, 0.12, 0.7, 0.8, 3.0, 5.0, 0.42, 0.70, true),
];

class _MeshPainter extends CustomPainter {
  final _Mesh mesh;
  _MeshPainter(this.mesh, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = mesh.canvas);
    final short = size.shortestSide;
    for (final blob in _blobs) {
      final cx = (blob.baseX + blob.ampX * math.sin(mesh.phase * blob.freqX + blob.phaseX)) * size.width;
      final cy = (blob.baseY + blob.ampY * math.cos(mesh.phase * blob.freqY + blob.phaseY)) * size.height;
      final r = blob.radius * short * (1 + 0.10 * math.sin(mesh.phase * 0.6 + blob.phaseX));
      final color = blob.useA ? mesh.a : mesh.b;
      final center = Offset(cx, cy);
      final rect = Rect.fromCircle(center: center, radius: r);
      final shader = RadialGradient(
        colors: [color.withValues(alpha: blob.opacity), color.withValues(alpha: 0.0)],
      ).createShader(rect);
      canvas.drawCircle(center, r, Paint()..shader = shader);
    }
  }

  @override
  bool shouldRepaint(_MeshPainter oldDelegate) => true;
}
