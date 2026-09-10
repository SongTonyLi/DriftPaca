import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:llamaseek/Utils/drift_speed.dart';
import 'package:llamaseek/Utils/motion.dart';
import 'package:llamaseek/Widgets/gradient/spiral_geometry.dart';

/// Full-bleed background that is a flat [idleColor] at rest. Only while
/// [isGenerating] does a halftone token spiral in [meshA]/[meshB] over [canvas]
/// slowly fade in — a rotating multi-arm spiral of dots streaming outward from a
/// glowing core, under a twinkling starfield; when generation stops it fades
/// back out to [idleColor] and the ticker stops, so an idle screen produces no
/// frames at all. Place at the bottom of a Stack behind content.
class FloatingGradientBackground extends StatefulWidget {
  final Color meshA;
  final Color meshB;
  final Color canvas; // tinted base under the spiral while generating
  final Color idleColor; // flat background at rest (white / near-black)
  final bool isGenerating;
  final bool isWelcome; // empty welcome screen — plays a brief starfield intro

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
  // Cap repaints to ~24fps; the motion is slow so painting every vsync wastes GPU.
  static const double _minFrameInterval = 1 / 24;
  // Fade (opacity change per second): ~2s in, ~3s out.
  static const double _fadeInPerSecond = 1 / 2.0;
  static const double _fadeOutPerSecond = 1 / 3.0;
  // Dissolve used when the drawn field has to change (intro <-> generating):
  // brisk, because it is dead time between two pictures rather than a mood fade.
  static const double _swapFadePerSecond = 1 / 0.45;
  // Below this, a non-generating field is fully hidden and the ticker stops.
  static const double _hideEpsilon = 0.001;

  late final Ticker _ticker;
  final SpiralField _field = SpiralField();
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);

  // The compiled program is immutable and reusable — cache it once for the app.
  static Future<ui.FragmentProgram>? _programFuture;
  ui.FragmentShader? _shader;

  Duration _last = Duration.zero;
  bool _resetClock = false;
  double _speed = kRestDriftSpeed;

  // Welcome-screen intro: the stars and a slow, beadless spiral show briefly,
  // then fade out.
  static const double _welcomeHoldSeconds = 5.0;
  static const double _welcomeFadeInPerSecond = 1 / 0.6;
  static const double _welcomeFadeOutPerSecond = 1 / 2.5;
  bool _animationsDisabled = false;
  bool _syncedMotion = false;
  // The intro is one-shot per visit to the welcome screen: once it has played
  // out, only leaving and coming back arms it again.
  bool _introDone = false;
  double _welcomeElapsed = 0;

  /// Whether the welcome intro is the field that should be on screen right now.
  /// Derived from the widget state every tick rather than latched, so a missed
  /// or duplicated trigger can never leave the field stuck in the wrong mode.
  bool get _wantsWelcome =>
      widget.isWelcome &&
      !widget.isGenerating &&
      !_introDone &&
      !_animationsDisabled;

  @override
  void initState() {
    super.initState();
    _field.a = widget.meshA;
    _field.b = widget.meshB;
    _field.canvas = widget.canvas;
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
    // Only arm the intro — the tick loop dissolves into the welcome field on its
    // own. Forcing the field to a fresh state here is what made a restart flash.
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

  /// Reduced motion: no spin, no intro, no frames — just the end state.
  void _settleWithoutMotion() {
    _ticker.stop();
    _field
      ..welcome = false
      ..opacity = widget.isGenerating ? 1.0 : 0.0;
    _repaint.value++;
  }

  Future<void> _loadShader() async {
    try {
      _programFuture ??=
          ui.FragmentProgram.fromAsset('shaders/halftone_spiral.frag');
      final program = await _programFuture!;
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
    } catch (e, st) {
      // Shader unavailable (headless test env / unsupported renderer / a broken
      // .frag): stay on the flat idleColor fallback. Keep the cached future so
      // we don't re-attempt a load that fails the same way, and log in debug so
      // a real regression hiding behind the plausible flat fallback is visible.
      assert(() {
        debugPrint(
            'FloatingGradientBackground: halftone_spiral.frag failed to load: $e\n$st');
        return true;
      }());
    }
  }

  @override
  void didUpdateWidget(FloatingGradientBackground old) {
    super.didUpdateWidget(old);
    // Colors are read live by the painter; keep them current (also updates the
    // flat idleColor via a fresh painter + repaint on the rebuild that follows).
    _field.a = widget.meshA;
    _field.b = widget.meshB;
    _field.canvas = widget.canvas;
    if (_animationsDisabled) {
      _settleWithoutMotion();
      return;
    }
    if (!widget.isWelcome) {
      _introDone = false; // leaving the welcome screen arms the next visit
    }
    if (widget.isGenerating && !old.isGenerating) {
      // Generation starts: wake the field. Any visible intro hands over to it in
      // _onTick by dissolving out first, so the picture never cuts.
      _wake();
    } else if (!widget.isGenerating && widget.isWelcome && !old.isWelcome) {
      // Returned to the empty welcome screen: replay the starfield intro.
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
    if (_field.welcome) {
      _welcomeElapsed += dt;
      _field.phase += dt; // the intro runs on real seconds
    } else {
      _speed = easeDriftSpeed(
          _speed, targetDriftSpeed(isGenerating: widget.isGenerating), dt);
      _field.phase += dt * _baseRate * _speed;
    }

    // The welcome intro and the generating spiral are two different pictures,
    // so the drawn field may only change while nothing is visible: when the two
    // disagree the current one fades out first and the swap lands at zero
    // opacity. Every transition is then a dissolve through the flat idle colour
    // instead of a one-frame jump cut.
    final swapping = _field.welcome != _wantsWelcome;
    final show = !swapping &&
        (widget.isGenerating ||
            (_field.welcome && _welcomeElapsed < _welcomeHoldSeconds));
    final double rate;
    if (swapping) {
      rate = _swapFadePerSecond;
    } else if (show) {
      rate = _field.welcome ? _welcomeFadeInPerSecond : _fadeInPerSecond;
    } else {
      rate = _field.welcome ? _welcomeFadeOutPerSecond : _fadeOutPerSecond;
    }
    _field.opacity = show
        ? math.min(1.0, _field.opacity + dt * rate)
        : math.max(0.0, _field.opacity - dt * rate);

    if (_field.opacity <= _hideEpsilon) {
      _field.opacity = 0;
      if (_field.welcome && _welcomeElapsed >= _welcomeHoldSeconds) {
        _introDone = true; // the one-shot intro has run for this welcome screen
      }
      if (_field.welcome != _wantsWelcome) {
        _field.welcome = _wantsWelcome;
        _field.phase = 0; // each field starts from its own rest configuration
        _welcomeElapsed = 0;
      }
    }

    _repaint.value++; // repaint only the painter, no widget rebuild

    // Nothing visible and nothing pending: flat idle, no frames.
    if (!widget.isGenerating && !_wantsWelcome && _field.opacity <= 0) {
      _ticker.stop();
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
    // One full-screen shader pass, and nothing else: the dots and stars are the
    // effect, so there is no frosted-glass layer over them (a blur would only
    // smear them back into a wash). Legibility is handled in the field itself —
    // see spiralLook, which holds the dot intensity back over a light idle.
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        isComplex: true,
        willChange: true,
        painter: _SpiralPainter(_field, widget.idleColor, _shader, _repaint),
      ),
    );
  }
}

/// Paints a flat [idleColor] at rest; while [field.opacity] > 0 it draws the
/// whole halftone spiral in a single full-screen [shader] pass (see
/// shaders/halftone_spiral.frag). At opacity 0 — and before the shader has
/// loaded — it is just the flat colour, so idle rendering is one rect and the
/// host stops ticking.
class _SpiralPainter extends CustomPainter {
  final SpiralField field;
  final Color idleColor;
  final ui.FragmentShader? shader;
  final Paint _bgPaint = Paint();
  final Paint _fieldPaint = Paint();

  _SpiralPainter(this.field, this.idleColor, this.shader, Listenable repaint)
      : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final o = field.opacity;
    final fs = shader;
    if (fs == null || o <= 0) {
      canvas.drawRect(rect, _bgPaint..color = idleColor); // flat idle, no shader
      return;
    }
    final u = buildSpiralUniforms(field, idleColor, size);
    for (var k = 0; k < u.length; k++) {
      fs.setFloat(k, u[k]);
    }
    canvas.drawRect(rect, _fieldPaint..shader = fs);
  }

  @override
  bool shouldRepaint(_SpiralPainter old) => true;
}
