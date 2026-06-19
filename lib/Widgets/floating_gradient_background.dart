import 'dart:math' as math;
import 'dart:ui' as ui;

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
  final bool isWelcome; // empty welcome screen — plays a brief corner-breathe intro

  const FloatingGradientBackground({
    super.key,
    required this.meshA,
    required this.meshB,
    required this.canvas,
    required this.idleColor,
    required this.isGenerating,
    this.isWelcome = false,
  });

  @override
  State<FloatingGradientBackground> createState() =>
      _FloatingGradientBackgroundState();
}

class _FloatingGradientBackgroundState extends State<FloatingGradientBackground>
    with SingleTickerProviderStateMixin {
  static const double _restLoopSeconds = 15.0; // medium drift
  static final double _baseRate = 2 * math.pi / _restLoopSeconds;
  // Cap repaints to ~24fps; the drift is slow so painting every vsync wastes GPU.
  static const double _minFrameInterval = 1 / 24;
  // "Very slow" fade (opacity change per second): ~5s in, ~8s out.
  static const double _fadeInPerSecond = 1 / 5.0;
  static const double _fadeOutPerSecond = 1 / 8.0;
  // Below this, a non-generating mesh is fully hidden and the ticker stops.
  static const double _hideEpsilon = 0.001;

  late final Ticker _ticker;
  final Mesh _mesh = Mesh();
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);

  // The compiled program is immutable and reusable — cache it once for the app.
  static Future<ui.FragmentProgram>? _programFuture;
  ui.FragmentShader? _shader;

  Duration _last = Duration.zero;
  bool _resetClock = false;
  double _speed = kRestDriftSpeed;

  // Welcome-screen intro: four corner blobs breathe briefly, then fade out.
  static const double _welcomeHoldSeconds = 5.0;
  static const double _welcomeFadeInPerSecond = 1 / 0.8;
  static const double _welcomeFadeOutPerSecond = 1 / 4.0;
  bool _introActive = false;
  double _welcomeElapsed = 0;

  @override
  void initState() {
    super.initState();
    _mesh.a = widget.meshA;
    _mesh.b = widget.meshB;
    _mesh.canvas = widget.canvas;
    _ticker = createTicker(_onTick);
    _loadShader();
    // Animate if we open mid-generation; or play the welcome intro if we open on
    // the empty welcome screen. Otherwise stay flat/idle.
    if (widget.isGenerating) {
      _ticker.start();
    } else if (widget.isWelcome) {
      _startWelcomeIntro();
    }
  }

  void _startWelcomeIntro() {
    _mesh.welcome = true;
    _introActive = true;
    _welcomeElapsed = 0;
    _mesh.opacity = 0;
    _resetClock = true;
    if (!_ticker.isActive) _ticker.start();
  }

  Future<void> _loadShader() async {
    try {
      _programFuture ??= ui.FragmentProgram.fromAsset('shaders/mesh.frag');
      final program = await _programFuture!;
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
    } catch (e, st) {
      // Shader unavailable (headless test env / unsupported renderer / a broken
      // mesh.frag): stay on the flat idleColor fallback. Keep the cached future
      // so we don't re-attempt a load that fails the same way, and log in debug
      // so a real regression hiding behind the plausible flat fallback is visible.
      assert(() {
        debugPrint('FloatingGradientBackground: mesh.frag failed to load: $e\n$st');
        return true;
      }());
    }
  }

  @override
  void didUpdateWidget(FloatingGradientBackground old) {
    super.didUpdateWidget(old);
    // Colors are read live by the painter; keep them current (also updates the
    // flat idleColor via a fresh painter + repaint on the rebuild that follows).
    _mesh.a = widget.meshA;
    _mesh.b = widget.meshB;
    _mesh.canvas = widget.canvas;
    if (widget.isGenerating && !old.isGenerating) {
      // Generation starts: wake the (conversation) mesh; cancel any welcome intro.
      _introActive = false;
      if (!_ticker.isActive) {
        _resetClock = true;
        _ticker.start();
      }
    } else if (!widget.isGenerating && widget.isWelcome && !old.isWelcome) {
      // Returned to the empty welcome screen: replay the corner-breathe intro.
      _startWelcomeIntro();
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
    if (dt < _minFrameInterval) return; // ~24fps throttle
    _last = elapsed;

    if (widget.isGenerating) {
      // Conversation: fade the drifting mesh in.
      _mesh.welcome = false;
      _introActive = false;
      _mesh.opacity = math.min(1.0, _mesh.opacity + dt * _fadeInPerSecond);
      _speed =
          easeDriftSpeed(_speed, targetDriftSpeed(isGenerating: true), dt);
      _mesh.phase += dt * _baseRate * _speed;
    } else if (_introActive) {
      // Welcome intro: appear, breathe the corners for the hold, then fade out.
      _mesh.welcome = true;
      _welcomeElapsed += dt;
      if (_welcomeElapsed < _welcomeHoldSeconds) {
        _mesh.opacity =
            math.min(1.0, _mesh.opacity + dt * _welcomeFadeInPerSecond);
      } else {
        _mesh.opacity =
            math.max(0.0, _mesh.opacity - dt * _welcomeFadeOutPerSecond);
      }
      _mesh.phase += dt; // corner breathe runs on real seconds
    } else {
      // Generation ended: fade the conversation mesh back out.
      _mesh.welcome = false;
      _mesh.opacity = math.max(0.0, _mesh.opacity - dt * _fadeOutPerSecond);
      _speed =
          easeDriftSpeed(_speed, targetDriftSpeed(isGenerating: false), dt);
      _mesh.phase += dt * _baseRate * _speed;
    }

    _repaint.value++; // repaint only the painter, no widget rebuild

    // Once fully faded out with nothing active, stop: flat idle, no frames.
    if (!widget.isGenerating && _mesh.opacity <= _hideEpsilon) {
      if (_introActive && _welcomeElapsed >= _welcomeHoldSeconds) {
        _introActive = false;
      }
      if (!_introActive) {
        _ticker.stop();
        _mesh.welcome = false;
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shader?.dispose();
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
        painter: _MeshPainter(_mesh, widget.idleColor, _shader, _repaint),
      ),
    );
  }
}

/// Paints a flat [idleColor] at rest; while [mesh.opacity] > 0 it draws the whole
/// six-blob mesh in a single full-screen [shader] pass (see shaders/mesh.frag).
/// At opacity 0 — and before the shader has loaded — it is just the flat colour,
/// so idle rendering is one rect and the host stops ticking.
class _MeshPainter extends CustomPainter {
  final Mesh mesh;
  final Color idleColor;
  final ui.FragmentShader? shader;
  final Paint _bgPaint = Paint();
  final Paint _meshPaint = Paint();

  _MeshPainter(this.mesh, this.idleColor, this.shader, Listenable repaint)
      : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final o = mesh.opacity;
    final fs = shader;
    if (fs == null || o <= 0) {
      canvas.drawRect(rect, _bgPaint..color = idleColor); // flat idle, no shader
      return;
    }
    final u = buildMeshUniforms(mesh, idleColor, size);
    for (var k = 0; k < u.length; k++) {
      fs.setFloat(k, u[k]);
    }
    canvas.drawRect(rect, _meshPaint..shader = fs);
  }

  @override
  bool shouldRepaint(_MeshPainter old) => true;
}
