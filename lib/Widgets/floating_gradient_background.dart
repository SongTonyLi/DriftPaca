import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:llamaseek/Utils/drift_speed.dart';
import 'package:llamaseek/Utils/motion.dart';
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
  // Fade (opacity change per second): ~2s in, ~3s out.
  static const double _fadeInPerSecond = 1 / 2.0;
  static const double _fadeOutPerSecond = 1 / 3.0;
  // Dissolve used when the drawn field has to change (intro <-> mesh): brisk,
  // because it is dead time between two pictures rather than a mood fade.
  static const double _swapFadePerSecond = 1 / 0.45;
  // Below this, a non-generating mesh is fully hidden and the ticker stops.
  static const double _hideEpsilon = 0.001;

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

  // Welcome-screen intro: four corner blobs breathe briefly, then fade out.
  static const double _welcomeHoldSeconds = 5.0;
  static const double _welcomeFadeInPerSecond = 1 / 0.6;
  static const double _welcomeFadeOutPerSecond = 1 / 2.5;
  bool _animationsDisabled = false;
  bool _syncedMotion = false;
  // The intro is one-shot per visit to the welcome screen: once it has played
  // out, only leaving and coming back arms it again.
  bool _introDone = false;
  double _welcomeElapsed = 0;

  /// Whether the corner intro is the field that should be on screen right now.
  /// Derived from the widget state every tick rather than latched, so a missed
  /// or duplicated trigger can never leave the mesh stuck in the wrong field.
  bool get _wantsWelcome =>
      widget.isWelcome &&
      !widget.isGenerating &&
      !_introDone &&
      !_animationsDisabled;

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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = animationsDisabled(context);
    // This also fires for MediaQuery changes that have nothing to do with the
    // background — the keyboard sliding up, a rotation, a brightness switch —
    // and several times over while one of them animates. Only the reduced-motion
    // preference is ours to react to; treating the rest as a reason to re-sync
    // is what restarted the welcome intro every time the user tapped the prompt
    // field or left the page.
    if (_syncedMotion && disabled == _animationsDisabled) return;
    _syncedMotion = true;
    _animationsDisabled = disabled;
    if (disabled) {
      _settleWithoutMotion();
    } else if (widget.isGenerating) {
      _wake();
    } else if (widget.isWelcome && !_introDone) {
      _startWelcomeIntro();
    }
  }

  void _startWelcomeIntro() {
    if (_animationsDisabled) {
      _settleWithoutMotion();
      return;
    }
    // Only arm the intro — the tick loop dissolves into the corner field on its
    // own. Forcing the mesh to a fresh state here is what made a restart flash.
    _introDone = false;
    _welcomeElapsed = 0;
    _wake();
  }

  /// Starts the ticker if it is not already running. Re-baselines the clock only
  /// on a real start, since a running ticker's [Duration] is already continuous
  /// (resetting it there would drop a frame for nothing).
  void _wake() {
    if (_ticker.isActive) return;
    _resetClock = true;
    _ticker.start();
  }

  /// Reduced motion: no drift, no intro, no frames — just the end state.
  void _settleWithoutMotion() {
    _ticker.stop();
    _mesh
      ..welcome = false
      ..opacity = widget.isGenerating ? 1.0 : 0.0;
    _glassOpacity.value = _mesh.opacity;
    _repaint.value++;
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
    if (_animationsDisabled) {
      _settleWithoutMotion();
      return;
    }
    if (!widget.isWelcome) {
      _introDone = false; // leaving the welcome screen arms the next visit
    }
    if (widget.isGenerating && !old.isGenerating) {
      // Generation starts: wake the mesh. Any visible intro hands over to it in
      // _onTick by dissolving out first, so the picture never cuts.
      _wake();
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

    // Advance whichever field is currently drawn.
    if (_mesh.welcome) {
      _welcomeElapsed += dt;
      _mesh.phase += dt; // corner breathe/drift runs on real seconds
    } else {
      _speed = easeDriftSpeed(
          _speed, targetDriftSpeed(isGenerating: widget.isGenerating), dt);
      _mesh.phase += dt * _baseRate * _speed;
    }

    // The corner intro and the drifting mesh are two different pictures, so the
    // drawn field may only change while nothing is visible: when the two
    // disagree the current one fades out first and the swap lands at zero
    // opacity. Every transition is then a dissolve through the flat idle colour
    // instead of a one-frame jump cut.
    final swapping = _mesh.welcome != _wantsWelcome;
    final show = !swapping &&
        (widget.isGenerating ||
            (_mesh.welcome && _welcomeElapsed < _welcomeHoldSeconds));
    final double rate;
    if (swapping) {
      rate = _swapFadePerSecond;
    } else if (show) {
      rate = _mesh.welcome ? _welcomeFadeInPerSecond : _fadeInPerSecond;
    } else {
      rate = _mesh.welcome ? _welcomeFadeOutPerSecond : _fadeOutPerSecond;
    }
    _mesh.opacity = show
        ? math.min(1.0, _mesh.opacity + dt * rate)
        : math.max(0.0, _mesh.opacity - dt * rate);

    if (_mesh.opacity <= _hideEpsilon) {
      _mesh.opacity = 0;
      if (_mesh.welcome && _welcomeElapsed >= _welcomeHoldSeconds) {
        _introDone = true; // the one-shot intro has run for this welcome screen
      }
      if (_mesh.welcome != _wantsWelcome) {
        _mesh.welcome = _wantsWelcome;
        _mesh.phase = 0; // each field starts from its own rest configuration
        _welcomeElapsed = 0;
      }
    }

    _repaint.value++; // repaint only the painter, no widget rebuild
    _glassOpacity.value = _mesh.opacity; // glass tracks the mesh

    // Nothing visible and nothing pending: flat idle, no frames.
    if (!widget.isGenerating && !_wantsWelcome && _mesh.opacity <= 0) {
      _glassOpacity.value = 0; // no lingering blur in the flat idle state
      _ticker.stop();
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
