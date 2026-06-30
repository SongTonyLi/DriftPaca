import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:llamaseek/Utils/drift_speed.dart';
import 'package:llamaseek/Widgets/gradient/mesh_geometry.dart';

/// Full-bleed background that is a flat [idleColor] at rest. Only while
/// [isGenerating] does a drifting mesh of soft radial-gradient blobs in
/// [meshA]/[meshB] over [canvas] slowly fade in; when generation stops the mesh
/// fades back out to [idleColor] and the ticker stops, so an idle screen
/// produces no frames at all. Place at the bottom of a Stack behind content.
///
/// While generating it also emits a slow, soft haptic "beat" locked to the same
/// drift clock as the blobs (see [_beatPhaseInterval]), so the device pulses
/// gently in time with the floating-blob motion — and only while it moves.
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
  // Fade (opacity change per second): ~2s in, ~3s out.
  static const double _fadeInPerSecond = 1 / 2.0;
  static const double _fadeOutPerSecond = 1 / 3.0;
  // Below this, a non-generating mesh is fully hidden and the ticker stops.
  static const double _hideEpsilon = 0.001;

  // A slow haptic "beat" locked to the blobs' own phase clock: one soft pulse
  // every [_beatPhaseInterval] radians of mesh phase, accrued from the very same
  // increment that drifts the blobs. So the beat rides the floating motion —
  // pacing a touch faster as the drift eases up to its generating speed, and
  // pausing whenever the motion pauses — rather than running on an independent
  // metronome. At the generating drift rate this lands a gentle pulse ~every 4s.
  static const double _beatPhaseInterval = 2.4;

  // The glass frost is a Gaussian blur computed on a [_blurScale]-downscaled
  // copy of the backdrop, then scaled back up. For a blur this soft the result
  // is visually ~identical to a full-resolution sigma-[_blurSigma] blur, but the
  // blur pass runs on ~_blurScale^2 of the pixels — cutting the dominant
  // per-frame GPU cost of the full-bleed glass layer. The filter never changes,
  // so build it once and reuse it.
  static const double _blurSigma = 38.0;
  static const double _blurScale = 0.5;
  final ui.ImageFilter _frost = _downscaledBlur(_blurSigma, _blurScale);

  late final Ticker _ticker;
  final Mesh _mesh = Mesh();
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);

  // The compiled program is immutable and reusable — cache it once for the app.
  static Future<ui.FragmentProgram>? _programFuture;
  ui.FragmentShader? _shader;

  Duration _last = Duration.zero;
  bool _resetClock = false;
  double _speed = kRestDriftSpeed;
  double _beatPhase = 0; // accrued mesh phase; a beat fires each _beatPhaseInterval

  // Welcome-screen intro: four corner blobs breathe briefly, then fade out.
  static const double _welcomeHoldSeconds = 5.0;
  static const double _welcomeFadeInPerSecond = 1 / 0.6;
  static const double _welcomeFadeOutPerSecond = 1 / 2.5;
  bool _introActive = false;
  double _welcomeElapsed = 0;

  // Glassy legibility layer over the blobs; its opacity tracks the mesh, so it is
  // absent in the flat idle (pure-colour) state and present whenever blobs show.
  final ValueNotifier<double> _glassOpacity = ValueNotifier<double>(0);

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
      _beatPhase = 0; // start this generation's beat fresh (first pulse ~one interval in)
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
      final dPhase = dt * _baseRate * _speed;
      _mesh.phase += dPhase;
      // Beat off the very same increment so the pulse stays in time with the
      // blobs; subtract (not zero) the interval to keep the cadence phase-locked.
      _beatPhase += dPhase;
      if (_beatPhase >= _beatPhaseInterval) {
        _beatPhase -= _beatPhaseInterval;
        HapticFeedback.lightImpact();
      }
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
    _glassOpacity.value = _mesh.opacity; // glass tracks the mesh

    // Once fully faded out with nothing active, stop: flat idle, no frames.
    if (!widget.isGenerating && _mesh.opacity <= _hideEpsilon) {
      if (_introActive && _welcomeElapsed >= _welcomeHoldSeconds) {
        _introActive = false;
      }
      if (!_introActive) {
        _glassOpacity.value = 0; // no lingering blur in the flat idle state
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
    _glassOpacity.dispose();
    super.dispose();
  }

  /// Builds a "downscale → blur → upscale" image filter: the [sigma] blur runs
  /// on a copy of the backdrop shrunk by [scale] (so it touches ~scale^2 of the
  /// pixels), then the result is scaled back up. For a soft blur this is
  /// visually ~indistinguishable from a full-resolution blur at far less cost.
  static ui.ImageFilter _downscaledBlur(double sigma, double scale) {
    ui.ImageFilter scaleBy(double s) => ui.ImageFilter.matrix(
          Float64List.fromList(<double>[
            s, 0, 0, 0, //
            0, s, 0, 0, //
            0, 0, 1, 0, //
            0, 0, 0, 1, //
          ]),
          filterQuality: ui.FilterQuality.low,
        );
    // compose applies `inner` first: shrink → blur → grow.
    return ui.ImageFilter.compose(
      outer: scaleBy(1 / scale),
      inner: ui.ImageFilter.compose(
        outer: ui.ImageFilter.blur(sigmaX: sigma * scale, sigmaY: sigma * scale),
        inner: scaleBy(scale),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Frosted "glass" over the blobs lifts text legibility; it blurs only the
    // mesh (below it), never the content (which sits above this widget).
    final glass = IgnorePointer(
      child: BackdropFilter(
        filter: _frost,
        child: Container(color: widget.idleColor.withValues(alpha: 0.12)),
      ),
    );
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            size: Size.infinite,
            isComplex: true,
            willChange: true,
            painter: _MeshPainter(_mesh, widget.idleColor, _shader, _repaint),
          ),
          ValueListenableBuilder<double>(
            valueListenable: _glassOpacity,
            child: glass,
            builder: (_, o, child) => o <= 0.01
                ? const SizedBox.shrink()
                : Opacity(opacity: o, child: child),
          ),
        ],
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
