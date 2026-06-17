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
  // Cap repaints to ~30fps. The drift is slow, so painting every vsync (up to
  // 120fps) wastes GPU/battery for no visible benefit.
  static const double _minFrameInterval = 1 / 30;

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
// Colors A and B are interleaved across the screen (A: top-left, bottom-right,
// center; B: top-right, bottom-left, center) so the two hues overlap and blend
// in the middle instead of separating into bands. Large radii keep the canvas
// almost fully covered, and amplitudes are large enough for clearly visible drift.
const List<_Blob> _blobs = [
  _Blob(0.22, 0.20, 0.16, 0.12, 1.0, 0.9, 0.0, 1.3, 0.95, 0.90, true),
  _Blob(0.80, 0.24, 0.15, 0.14, 0.8, 1.1, 2.1, 0.4, 0.92, 0.90, false),
  _Blob(0.24, 0.80, 0.14, 0.16, 1.2, 0.7, 4.0, 2.6, 0.95, 0.90, false),
  _Blob(0.80, 0.82, 0.16, 0.13, 0.9, 1.0, 1.2, 3.4, 0.90, 0.90, true),
  _Blob(0.50, 0.46, 0.22, 0.18, 0.7, 0.8, 3.0, 5.0, 0.78, 0.75, true),
  _Blob(0.46, 0.56, 0.20, 0.22, 1.1, 0.9, 5.2, 1.7, 0.76, 0.75, false),
];

class _MeshPainter extends CustomPainter {
  final _Mesh mesh;
  // Hoisted out of paint() so the always-on animation doesn't allocate a Paint
  // per blob every frame. Shaders still rebuild per frame (the blobs move), but
  // the Paint objects are reused.
  final Paint _bgPaint = Paint();
  final List<Paint> _blobPaints = List.generate(_blobs.length, (_) => Paint());

  _MeshPainter(this.mesh, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, _bgPaint..color = mesh.canvas);
    final short = size.shortestSide;
    for (var i = 0; i < _blobs.length; i++) {
      final blob = _blobs[i];
      final cx = (blob.baseX + blob.ampX * math.sin(mesh.phase * blob.freqX + blob.phaseX)) * size.width;
      final cy = (blob.baseY + blob.ampY * math.cos(mesh.phase * blob.freqY + blob.phaseY)) * size.height;
      final r = blob.radius * short * (1 + 0.10 * math.sin(mesh.phase * 0.6 + blob.phaseX));
      final color = blob.useA ? mesh.a : mesh.b;
      final center = Offset(cx, cy);
      final rect = Rect.fromCircle(center: center, radius: r);
      final shader = RadialGradient(
        // Hold the color through 40% of the radius before fading, so big blobs
        // fill area and overlap richly instead of being thin halos.
        colors: [
          color.withValues(alpha: blob.opacity),
          color.withValues(alpha: blob.opacity),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(rect);
      canvas.drawCircle(center, r, _blobPaints[i]..shader = shader);
    }
  }

  @override
  bool shouldRepaint(_MeshPainter oldDelegate) => true;
}
