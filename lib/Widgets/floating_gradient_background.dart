import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:llamaseek/Utils/drift_speed.dart';
import 'package:llamaseek/Widgets/gradient/mesh_geometry.dart';

/// Full-bleed background that is a flat [idleColor] at rest. Only while
/// [isGenerating] does a drifting mesh of soft radial-gradient blobs in
/// [meshA]/[meshB] over [canvas] slowly fade in; when generation stops the mesh
/// fades back out to [idleColor] and the ticker stops, so an idle screen
/// produces no frames at all. Place at the bottom of a Stack behind content.
class FloatingGradientBackground extends StatefulWidget {
  final Color meshA;
  final Color meshB;
  final Color canvas; // tinted base under the blobs while generating
  final Color idleColor; // flat background at rest (white / near-black)
  final bool isGenerating;

  const FloatingGradientBackground({
    super.key,
    required this.meshA,
    required this.meshB,
    required this.canvas,
    required this.idleColor,
    required this.isGenerating,
  });

  @override
  State<FloatingGradientBackground> createState() =>
      _FloatingGradientBackgroundState();
}

class _FloatingGradientBackgroundState extends State<FloatingGradientBackground>
    with SingleTickerProviderStateMixin {
  static const double _restLoopSeconds = 15.0; // medium drift
  static final double _baseRate = 2 * math.pi / _restLoopSeconds;
  // Cap repaints to ~30fps; the drift is slow so painting every vsync wastes GPU.
  static const double _minFrameInterval = 1 / 30;
  // "Very slow" fade (opacity change per second): ~5s in, ~8s out.
  static const double _fadeInPerSecond = 1 / 5.0;
  static const double _fadeOutPerSecond = 1 / 8.0;
  // Below this, a non-generating mesh is fully hidden and the ticker stops.
  static const double _hideEpsilon = 0.001;

  late final Ticker _ticker;
  final Mesh _mesh = Mesh();
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);

  Duration _last = Duration.zero;
  bool _resetClock = false;
  double _speed = kRestDriftSpeed;

  @override
  void initState() {
    super.initState();
    _mesh.a = widget.meshA;
    _mesh.b = widget.meshB;
    _mesh.canvas = widget.canvas;
    _ticker = createTicker(_onTick);
    // Only animate if we open mid-generation; otherwise stay flat/idle.
    if (widget.isGenerating) _ticker.start();
  }

  @override
  void didUpdateWidget(FloatingGradientBackground old) {
    super.didUpdateWidget(old);
    // Colors are read live by the painter; keep them current (also updates the
    // flat idleColor via a fresh painter + repaint on the rebuild that follows).
    _mesh.a = widget.meshA;
    _mesh.b = widget.meshB;
    _mesh.canvas = widget.canvas;
    // Generation starting wakes the ticker to fade the mesh in.
    if (widget.isGenerating && !_ticker.isActive) {
      _resetClock = true;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    // After a restart the ticker clock starts over; capture a baseline and skip
    // one frame so dt is never huge (no phase jump) or negative.
    if (_resetClock) {
      _last = elapsed;
      _resetClock = false;
      return;
    }
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    if (dt < _minFrameInterval) return; // ~30fps throttle
    _last = elapsed;

    // Fade the mesh toward the generation state (very slow).
    if (widget.isGenerating) {
      _mesh.opacity = math.min(1.0, _mesh.opacity + dt * _fadeInPerSecond);
    } else {
      _mesh.opacity = math.max(0.0, _mesh.opacity - dt * _fadeOutPerSecond);
    }

    // Drift: brisk while generating, gentle (rest) while fading out.
    _speed = easeDriftSpeed(
        _speed, targetDriftSpeed(isGenerating: widget.isGenerating), dt);
    _mesh.phase += dt * _baseRate * _speed;

    _repaint.value++; // repaint only the painter, no widget rebuild

    // Once fully faded out and not generating, stop: flat idle color, no frames.
    if (!widget.isGenerating && _mesh.opacity <= _hideEpsilon) {
      _ticker.stop();
    }
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
        painter: _MeshPainter(_mesh, widget.idleColor, _repaint),
      ),
    );
  }
}

/// Paints a flat [idleColor], then crossfades the tinted [Mesh.canvas] + the six
/// drifting blobs in over it at [Mesh.opacity]. At opacity 0 it is just the flat
/// colour (and the host stops ticking), so idle rendering is a single rect.
class _MeshPainter extends CustomPainter {
  final Mesh mesh;
  final Color idleColor;
  final Paint _bgPaint = Paint();
  final List<Paint> _blobPaints = List.generate(kBlobs.length, (_) => Paint());

  _MeshPainter(this.mesh, this.idleColor, Listenable repaint)
      : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, _bgPaint..color = idleColor);

    final o = mesh.opacity;
    if (o <= 0) return; // idle: just the flat colour

    // Tinted canvas fades in over the flat base.
    canvas.drawRect(rect, _bgPaint..color = mesh.canvas.withValues(alpha: o));
    for (var i = 0; i < kBlobs.length; i++) {
      final blob = kBlobs[i];
      final p = blobPlacement(blob, mesh.phase, size);
      final color = blob.useA ? mesh.a : mesh.b;
      final r = Rect.fromCircle(center: p.center, radius: p.radius);
      final shader = RadialGradient(
        colors: [
          color.withValues(alpha: blob.opacity * o),
          color.withValues(alpha: blob.opacity * o),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(r);
      canvas.drawCircle(p.center, p.radius, _blobPaints[i]..shader = shader);
    }
  }

  @override
  bool shouldRepaint(_MeshPainter old) => true;
}
