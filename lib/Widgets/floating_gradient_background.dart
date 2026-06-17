import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:llamaseek/Utils/drift_speed.dart';
import 'package:llamaseek/Utils/idle_activity_controller.dart';
import 'package:llamaseek/Widgets/gradient/blob_sprite.dart';
import 'package:llamaseek/Widgets/gradient/mesh_atlas_painter.dart';
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

  /// When supplied, the drift eases to a standstill and the ticker stops once
  /// the screen has been idle (no pointer/scroll) and no generation is running,
  /// resuming instantly on the next activity. Null => always animating.
  final IdleActivityController? activity;

  const FloatingGradientBackground({
    super.key,
    required this.meshA,
    required this.meshB,
    required this.canvas,
    required this.isGenerating,
    this.activity,
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
  // Drift is "stopped" once the eased speed falls below this; we then freeze the
  // ticker outright so no further frames are produced.
  static const double _freezeEpsilon = 0.003;

  late final Ticker _ticker;
  final Mesh _mesh = Mesh();
  late final ui.Image _sprite = bakeBlobSprite();
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);

  Duration _last = Duration.zero;
  bool _resetClock = false;
  double _speed = kRestDriftSpeed;
  double _colorT = 1.0;
  late Color _fromA, _fromB, _fromCanvas;

  @override
  void initState() {
    super.initState();
    _mesh.a = _fromA = widget.meshA;
    _mesh.b = _fromB = widget.meshB;
    _mesh.canvas = _fromCanvas = widget.canvas;
    widget.activity?.addListener(_onActivityChanged);
    _ticker = createTicker(_onTick)..start();
  }

  bool get _effectiveActive =>
      (widget.activity?.isActive ?? true) || widget.isGenerating;

  void _onActivityChanged() {
    // Resume instantly when the user (or generation) wakes the screen.
    if (_effectiveActive && !_ticker.isActive) {
      _resetClock = true;
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(FloatingGradientBackground old) {
    super.didUpdateWidget(old);
    if (old.activity != widget.activity) {
      old.activity?.removeListener(_onActivityChanged);
      widget.activity?.addListener(_onActivityChanged);
    }
    // Generation can wake a frozen screen.
    if (widget.isGenerating && !_ticker.isActive) {
      _resetClock = true;
      _ticker.start();
    }
    if (old.meshA != widget.meshA ||
        old.meshB != widget.meshB ||
        old.canvas != widget.canvas) {
      _fromA = _mesh.a;
      _fromB = _mesh.b;
      _fromCanvas = _mesh.canvas;
      _colorT = 0.0; // restart the color cross-fade; phase is untouched
      // A mid-fade screen must keep ticking to render the fade.
      if (!_ticker.isActive) {
        _resetClock = true;
        _ticker.start();
      }
    }
  }

  void _onTick(Duration elapsed) {
    // After a restart the ticker clock starts over; capture a fresh baseline
    // and skip one frame so dt is never huge (no phase jump) or negative.
    if (_resetClock) {
      _last = elapsed;
      _resetClock = false;
      return;
    }
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    // Throttle to ~30fps: skip sub-interval ticks to save battery. _last only
    // advances on a real frame, so dt accumulates and phase stays continuous.
    if (dt < _minFrameInterval) return;
    _last = elapsed;

    // isGenerating/activity are read live each tick (not handled in
    // didUpdateWidget, like phase) so the speed target tracks state immediately.
    _speed = easeDriftSpeed(
        _speed,
        targetDriftSpeed(
            isGenerating: widget.isGenerating, isActive: _effectiveActive),
        dt);
    _mesh.phase += dt * _baseRate * _speed;

    if (_colorT < 1.0) {
      _colorT = math.min(1.0, _colorT + dt / _colorFadeSeconds);
      final e = Curves.easeInOutCubic.transform(_colorT);
      _mesh.a = Color.lerp(_fromA, widget.meshA, e)!;
      _mesh.b = Color.lerp(_fromB, widget.meshB, e)!;
      _mesh.canvas = Color.lerp(_fromCanvas, widget.canvas, e)!;
    }
    _repaint.value++; // repaint only the painter, no widget rebuild

    // Freeze once idle and settled: stop ticking so no frames are produced
    // (which also halts any backdrop blur stacked above this layer). Wait for
    // any color cross-fade to finish so we never freeze mid-fade.
    if (!_effectiveActive && _colorT >= 1.0 && _speed < _freezeEpsilon) {
      _speed = 0.0;
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    widget.activity?.removeListener(_onActivityChanged);
    _ticker.dispose();
    _repaint.dispose();
    _sprite.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        isComplex: true,
        willChange: true,
        painter: MeshAtlasPainter(_mesh, _sprite, _repaint),
      ),
    );
  }
}
