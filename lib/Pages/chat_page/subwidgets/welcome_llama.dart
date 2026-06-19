import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// An animated llama that trots across the welcome screen.
///
/// Motion is driven by a single [Ticker] whose phase advances on real elapsed
/// time, but repaints are throttled to [_minFrameInterval] (~30fps). The trot
/// (600ms) and walk (5s, reversing) cycles are unchanged — we just sample them
/// less often than the display's native 60/120Hz, which roughly halves (60Hz)
/// or quarters (120Hz) the per-frame paint cost on this otherwise-idle screen
/// with no perceptible difference for a small stylized mascot.
class WelcomeLlama extends StatefulWidget {
  const WelcomeLlama({super.key});

  @override
  State<WelcomeLlama> createState() => _WelcomeLlamaState();
}

class _WelcomeLlamaState extends State<WelcomeLlama>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);

  // ~30fps cap: a gentle trot does not need 60/120fps.
  static const double _minFrameInterval = 1 / 30;
  static const double _trotSeconds = 0.6; // one gait cycle
  static const double _walkSeconds = 5.0; // one direction of the patrol

  Duration _last = Duration.zero;
  bool _resetClock = true;
  double _clock = 0; // accumulated real seconds (continuous across pauses)
  double _lastPaintClock = 0;

  // Sampled animation state read by build()/painter.
  double _trotValue = 0;
  double _walkValue = 0;
  bool _facingLeft = false;

  // Color-derived geometry/colors, recomputed only when the theme color changes.
  _LlamaVisuals? _visuals;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    // Skip one frame after (re)start so dt is never huge or negative.
    if (_resetClock) {
      _last = elapsed;
      _resetClock = false;
      return;
    }
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _clock += dt;

    if (_clock - _lastPaintClock < _minFrameInterval) return; // ~30fps throttle
    _lastPaintClock = _clock;

    _trotValue = (_clock / _trotSeconds) % 1.0;
    // Walk patrols 0->1 then 1->0 (period 2x _walkSeconds); facing flips on the
    // return leg, matching the previous repeat(reverse: true) controller.
    final w = (_clock / _walkSeconds) % 2.0;
    if (w < 1.0) {
      _walkValue = w;
      _facingLeft = false;
    } else {
      _walkValue = 2.0 - w;
      _facingLeft = true;
    }

    _repaint.value++;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _ticker.stop();
    } else if (state == AppLifecycleState.resumed) {
      if (!_ticker.isActive) {
        _resetClock = true; // resume the phase where it left off, no jump
        _ticker.start();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bodyColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFF0EBE4)
        : const Color(0xFFD6CCC0);
    if (_visuals == null || _visuals!.body != bodyColor) {
      _visuals = _LlamaVisuals.build(bodyColor);
    }

    return ValueListenableBuilder<int>(
      valueListenable: _repaint,
      builder: (context, _, __) {
        final dx = (_walkValue - 0.5) * 50;
        return Transform.translate(
          offset: Offset(dx, 0),
          child: Transform.flip(
            flipX: _facingLeft,
            child: CustomPaint(
              size: const Size(130, 120),
              painter: _LlamaPainter(phase: _trotValue, visuals: _visuals!),
            ),
          ),
        );
      },
    );
  }
}

/// One precomputed fleece puff: a fixed position/radius/colour that depends only
/// on the body colour (deterministic Random(42)), so it is built once per colour.
class _Puff {
  final double x, y, r;
  final Color color;
  const _Puff(this.x, this.y, this.r, this.color);
}

/// All body-colour-derived values for the llama, computed once and reused across
/// frames. Previously these (HSL darken/lighten conversions and a Random(42)
/// fleece layout) were recomputed on every paint.
class _LlamaVisuals {
  final Color body;
  final Color lightFluff; // lighten 0.06
  final Color darkFluff; // darken 0.04
  final Color outline; // darken 0.18 (body + neck)
  final Color headColor; // darken 0.05
  final Color headOutline; // darken 0.22
  final Color muzzle; // lighten 0.08
  final Color nostril; // darken 0.40
  final Color mouth; // darken 0.25
  final Color earOutline; // darken 0.20
  final Color legBack; // darken 0.12
  final Color legFront; // darken 0.08
  final Color hoof; // darken 0.35
  final Color dust; // darken 0.10
  final List<_Puff> puffs; // 18 inner-fleece puffs
  final List<double> highlightRadii; // 5 top-highlight radii

  const _LlamaVisuals({
    required this.body,
    required this.lightFluff,
    required this.darkFluff,
    required this.outline,
    required this.headColor,
    required this.headOutline,
    required this.muzzle,
    required this.nostril,
    required this.mouth,
    required this.earOutline,
    required this.legBack,
    required this.legFront,
    required this.hoof,
    required this.dust,
    required this.puffs,
    required this.highlightRadii,
  });

  factory _LlamaVisuals.build(Color body) {
    Color darken(double amt) {
      final hsl = HSLColor.fromColor(body);
      return hsl.withLightness((hsl.lightness - amt).clamp(0.0, 1.0)).toColor();
    }

    Color lighten(double amt) {
      final hsl = HSLColor.fromColor(body);
      return hsl.withLightness((hsl.lightness + amt).clamp(0.0, 1.0)).toColor();
    }

    final lightFluff = lighten(0.06);
    final darkFluff = darken(0.04);

    // Deterministic fleece layout — same RNG sequence as the original painter:
    // 18 puffs (3 draws each) then 5 highlight radii, all from Random(42).
    final rng = Random(42);
    final puffs = <_Puff>[];
    for (int i = 0; i < 18; i++) {
      final fx = 16.0 + rng.nextDouble() * 56;
      final fy = 34.0 + rng.nextDouble() * 32;
      final fr = 3.5 + rng.nextDouble() * 3.5;
      final c = i % 3 == 0 ? lightFluff : (i % 3 == 1 ? body : darkFluff);
      puffs.add(_Puff(fx, fy, fr, c));
    }
    final highlightRadii = <double>[
      for (int i = 0; i < 5; i++) 3.0 + rng.nextDouble() * 2,
    ];

    return _LlamaVisuals(
      body: body,
      lightFluff: lightFluff,
      darkFluff: darkFluff,
      outline: darken(0.18),
      headColor: darken(0.05),
      headOutline: darken(0.22),
      muzzle: lighten(0.08),
      nostril: darken(0.4),
      mouth: darken(0.25),
      earOutline: darken(0.2),
      legBack: darken(0.12),
      legFront: darken(0.08),
      hoof: darken(0.35),
      dust: darken(0.1),
      puffs: puffs,
      highlightRadii: highlightRadii,
    );
  }
}

// Static fleece-edge scallop positions [x, y, radius]; phase only wobbles them.
const List<List<double>> _scallops = [
  // Top row (back)
  [14.0, 36.0, 8.0], [24.0, 30.0, 9.0], [35.0, 28.0, 9.5],
  [46.0, 29.0, 9.0], [56.0, 31.0, 8.5], [66.0, 34.0, 8.0],
  // Left side (rump)
  [10.0, 48.0, 8.0], [8.0, 56.0, 7.5], [12.0, 64.0, 7.0],
  // Right side (chest)
  [74.0, 44.0, 7.0], [76.0, 54.0, 7.0], [74.0, 64.0, 6.5],
];

const List<List<double>> _neckFluff = [
  [62.0, 36.0, 6.0], [63.0, 28.0, 5.5], [65.0, 22.0, 5.0],
  [67.0, 16.0, 5.0], [70.0, 10.0, 4.5],
];

const List<List<double>> _chestFluff = [
  [80.0, 38.0, 5.0], [80.0, 30.0, 4.5], [80.0, 22.0, 4.0],
  [82.0, 14.0, 4.0],
];

class _LlamaPainter extends CustomPainter {
  final double phase;
  final _LlamaVisuals visuals;

  _LlamaPainter({required this.phase, required this.visuals});

  @override
  void paint(Canvas canvas, Size size) {
    final lp = phase * 2 * pi;
    final bounce = sin(lp) * 1.8;

    canvas.save();
    canvas.translate(4, 4);

    // Draw order: back legs, tail, body fleece, neck, head, front legs
    _drawBackLegs(canvas, bounce, lp);
    _drawTail(canvas, bounce);
    _drawBody(canvas, bounce);
    _drawNeckWool(canvas, bounce);
    _drawFrontLegs(canvas, bounce, lp);
    _drawHead(canvas, bounce);
    _drawDust(canvas, bounce);

    canvas.restore();
  }

  void _drawDust(Canvas canvas, double bounce) {
    for (int i = 0; i < 3; i++) {
      final p = (phase + i * 0.33) % 1.0;
      canvas.drawCircle(
        Offset(20 - p * 18, 105 + p * 4),
        1.0 + p * 2.0,
        Paint()..color = visuals.dust.withValues(alpha: (1.0 - p) * 0.1),
      );
    }
  }

  // ── BODY: massive fluffy fleece ──

  void _drawBody(Canvas canvas, double bounce) {
    final by = bounce;

    // Core body shape
    final core = Path();
    core.moveTo(72, 72 + by);   // front bottom
    core.quadraticBezierTo(50, 78 + by, 22, 72 + by); // belly
    core.quadraticBezierTo(8, 62 + by, 10, 46 + by);  // rump up
    core.quadraticBezierTo(12, 34 + by, 24, 32 + by); // back
    core.lineTo(60, 32 + by);                          // top
    core.quadraticBezierTo(76, 34 + by, 78, 46 + by); // chest
    core.quadraticBezierTo(80, 58 + by, 72, 72 + by); // front down
    core.close();
    canvas.drawPath(core, Paint()..color = visuals.body);

    // Outer fleece edge — big scallops along top & sides
    for (final s in _scallops) {
      final wobble = sin(phase * 3 * pi + s[0] * 0.2) * 0.5;
      canvas.drawCircle(
        Offset(s[0], s[1] + by + wobble),
        s[2],
        Paint()..color = visuals.body,
      );
    }

    // Inner fleece detail — smaller puffs for texture (fixed layout)
    for (int i = 0; i < visuals.puffs.length; i++) {
      final p = visuals.puffs[i];
      final wobble = sin(phase * 4 * pi + i * 0.8) * 0.4;
      canvas.drawCircle(
        Offset(p.x, p.y + by + wobble),
        p.r,
        Paint()..color = p.color,
      );
    }

    // White highlights on top
    for (int i = 0; i < 5; i++) {
      final hx = 22.0 + i * 10;
      final hy = 32.0 + by + sin(phase * 3 * pi + i) * 0.5;
      canvas.drawCircle(
        Offset(hx, hy),
        visuals.highlightRadii[i],
        Paint()..color = Colors.white.withValues(alpha: 0.2),
      );
    }

    // Subtle outline
    canvas.drawPath(
      core,
      Paint()
        ..color = visuals.outline
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke,
    );
  }

  // ── NECK: thick, woolly, straight, tapering up ──

  void _drawNeckWool(Canvas canvas, double bounce) {
    final by = bounce;

    // Neck base shape — wide at bottom, narrower at top
    final neck = Path();
    neck.moveTo(62, 36 + by);      // base left (connects to body)
    neck.quadraticBezierTo(64, 20 + by * 0.5, 72, 6 + by * 0.2);  // left edge up
    neck.lineTo(84, 8 + by * 0.2);  // top
    neck.quadraticBezierTo(82, 22 + by * 0.5, 80, 40 + by); // right edge down
    neck.close();
    canvas.drawPath(neck, Paint()..color = visuals.body);

    // Neck wool scallops along left edge (visible fluffy side)
    for (final f in _neckFluff) {
      final wobble = sin(phase * 3 * pi + f[1] * 0.3) * 0.4;
      canvas.drawCircle(
        Offset(f[0], f[1] + by * (f[1] / 40) + wobble),
        f[2],
        Paint()..color = visuals.body,
      );
    }

    // Right edge fluff (chest side)
    for (final f in _chestFluff) {
      final wobble = sin(phase * 3 * pi + f[1] * 0.2 + 1) * 0.3;
      canvas.drawCircle(
        Offset(f[0], f[1] + by * (f[1] / 40) + wobble),
        f[2],
        Paint()..color = visuals.body,
      );
    }

    // Light highlights on neck
    canvas.drawCircle(
      Offset(74, 20 + by * 0.4),
      3.5,
      Paint()..color = Colors.white.withValues(alpha: 0.15),
    );
    canvas.drawCircle(
      Offset(72, 30 + by * 0.6),
      3.0,
      Paint()..color = Colors.white.withValues(alpha: 0.12),
    );

    // Subtle outline
    canvas.drawPath(
      neck,
      Paint()
        ..color = visuals.outline
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke,
    );
  }

  // ── HEAD: small, compact, elegant ──

  void _drawHead(Canvas canvas, double bounce) {
    final by = bounce * 0.2;
    final headColor = visuals.headColor;
    final outlinePaint = Paint()
      ..color = visuals.headOutline
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Head shape — small, compact, slightly triangular profile
    final head = Path();
    head.moveTo(76, 6 + by);       // back of head
    head.quadraticBezierTo(82, 0 + by, 90, 2 + by);   // forehead
    head.quadraticBezierTo(95, 4 + by, 96, 8 + by);   // front of face
    head.quadraticBezierTo(96, 13 + by, 92, 14 + by);  // chin
    head.quadraticBezierTo(84, 16 + by, 78, 12 + by);  // jaw
    head.quadraticBezierTo(74, 10 + by, 76, 6 + by);   // back
    head.close();
    canvas.drawPath(head, Paint()..color = headColor);
    canvas.drawPath(head, outlinePaint);

    // Muzzle area — slightly lighter
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(94, 10 + by),
        width: 5,
        height: 6,
      ),
      Paint()..color = visuals.muzzle,
    );

    // Nostril
    canvas.drawCircle(
      Offset(95, 10 + by),
      0.8,
      Paint()..color = visuals.nostril,
    );

    // Mouth line
    canvas.drawArc(
      Rect.fromCenter(center: Offset(93, 12 + by), width: 4, height: 2),
      0.2, 2.5, false,
      Paint()
        ..color = visuals.mouth
        ..strokeWidth = 0.7
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Eye
    canvas.drawOval(
      Rect.fromCenter(center: Offset(88, 6.5 + by), width: 4.5, height: 4),
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
    canvas.drawCircle(Offset(88.5, 6.8 + by), 1.8,
      Paint()..color = const Color(0xFF2A1F14));
    canvas.drawCircle(Offset(88.8, 7 + by), 0.9,
      Paint()..color = const Color(0xFF0F0A05));
    // Eye sparkle
    canvas.drawCircle(Offset(87.5, 6 + by), 0.7,
      Paint()..color = Colors.white.withValues(alpha: 0.85));

    // Ears — upright, banana-curved, small
    final earFlop = sin(phase * 2 * pi) * 1.0;
    _drawEar(canvas, 80, 2 + by, -3, -10 + earFlop);
    _drawEar(canvas, 86, 1 + by, 2, -11 - earFlop);
  }

  void _drawEar(Canvas canvas, double bx, double by, double dx, double dy) {
    final ear = Path();
    ear.moveTo(bx - 1.5, by);
    ear.quadraticBezierTo(bx + dx - 1, by + dy, bx + dx + 1, by + dy + 1);
    ear.quadraticBezierTo(bx + dx + 3, by + dy + 3, bx + 1.5, by);
    ear.close();
    canvas.drawPath(ear, Paint()..color = visuals.body);
    canvas.drawPath(ear, Paint()
      ..color = visuals.earOutline
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke);

    // Inner ear pink
    final inner = Path();
    inner.moveTo(bx - 0.3, by);
    inner.quadraticBezierTo(bx + dx, by + dy + 3, bx + dx + 1, by + dy + 3.5);
    inner.quadraticBezierTo(bx + dx + 1.8, by + dy + 4, bx + 0.5, by);
    inner.close();
    canvas.drawPath(inner,
      Paint()..color = const Color(0xFFD4A69A).withValues(alpha: 0.35));
  }

  // ── TAIL: fluffy, hanging down ──

  void _drawTail(Canvas canvas, double bounce) {
    final by = bounce;
    final tailSway = sin(phase * 3 * pi) * 3;
    final tx = 10.0 + tailSway * 0.3;
    final ty = 42.0 + by;

    // Fluffy tail — cluster of overlapping circles hanging down
    final puffs = [
      [tx + 2, ty - 2, 5.0],
      [tx - 1, ty + 5, 5.5],
      [tx + 1, ty + 12, 5.0],
      [tx - 2 + tailSway * 0.4, ty + 18, 4.5],
      [tx + 3, ty + 2, 4.0],
      [tx - 1, ty + 9, 4.0],
      [tx + tailSway * 0.3, ty + 15, 3.5],
    ];
    for (final p in puffs) {
      canvas.drawCircle(
        Offset(p[0], p[1]),
        p[2],
        Paint()..color = visuals.body,
      );
    }
    // Highlight
    canvas.drawCircle(
      Offset(tx + 1, ty + 4),
      2.5,
      Paint()..color = Colors.white.withValues(alpha: 0.15),
    );
  }

  // ── LEGS: thin, long, with hooves ──

  void _drawBackLegs(Canvas canvas, double bounce, double lp) {
    final legPaint = Paint()
      ..color = visuals.legBack
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    final hoofPaint = Paint()..color = visuals.hoof;
    final by = bounce;

    // Back-left
    final s1 = sin(lp + pi * 0.6) * 7;
    _drawLeg(canvas, 24, 68 + by, s1, 100, legPaint, hoofPaint);
    // Back-right
    final s2 = sin(lp + pi * 1.6) * 7;
    _drawLeg(canvas, 30, 68 + by, s2, 100, legPaint, hoofPaint);
  }

  void _drawFrontLegs(Canvas canvas, double bounce, double lp) {
    final legPaint = Paint()
      ..color = visuals.legFront
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    final hoofPaint = Paint()..color = visuals.hoof;
    final by = bounce;

    // Front-left
    final s1 = sin(lp) * 8;
    _drawLeg(canvas, 64, 68 + by, s1, 100, legPaint, hoofPaint);
    // Front-right
    final s2 = sin(lp + pi) * 8;
    _drawLeg(canvas, 70, 68 + by, s2, 100, legPaint, hoofPaint);
  }

  void _drawLeg(Canvas c, double x, double top, double swing, double ground,
      Paint leg, Paint hoof) {
    final knee = Offset(x + swing * 0.3, top + (ground - top) * 0.55);
    c.drawLine(Offset(x, top), knee, leg);
    c.drawLine(knee, Offset(x + swing, ground), leg);
    // Small hoof
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + swing, ground + 1.5),
          width: 4.5, height: 3.5,
        ),
        const Radius.circular(1.2),
      ),
      hoof,
    );
  }

  @override
  bool shouldRepaint(_LlamaPainter old) =>
      phase != old.phase || visuals != old.visuals;
}
