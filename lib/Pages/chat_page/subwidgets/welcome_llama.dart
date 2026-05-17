import 'dart:math';
import 'package:flutter/material.dart';

/// An animated llama that trots across the welcome screen.
class WelcomeLlama extends StatefulWidget {
  const WelcomeLlama({super.key});

  @override
  State<WelcomeLlama> createState() => _WelcomeLlamaState();
}

class _WelcomeLlamaState extends State<WelcomeLlama>
    with TickerProviderStateMixin {
  late AnimationController _trot;
  late AnimationController _walk;

  @override
  void initState() {
    super.initState();
    _trot = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat();
    _walk = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _trot.dispose();
    _walk.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_trot, _walk]),
      builder: (context, _) {
        final dx = (_walk.value - 0.5) * 50;
        final facingLeft = _walk.status == AnimationStatus.reverse;

        return Transform.translate(
          offset: Offset(dx, 0),
          child: Transform.flip(
            flipX: facingLeft,
            child: CustomPaint(
              size: const Size(130, 120),
              painter: _LlamaPainter(
                phase: _trot.value,
                bodyColor: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFFF0EBE4)
                    : const Color(0xFFD6CCC0),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LlamaPainter extends CustomPainter {
  final double phase;
  final Color bodyColor;

  _LlamaPainter({required this.phase, required this.bodyColor});

  Color _darken(Color c, double amt) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - amt).clamp(0.0, 1.0)).toColor();
  }

  Color _lighten(Color c, double amt) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness + amt).clamp(0.0, 1.0)).toColor();
  }

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
        Paint()..color = _darken(bodyColor, 0.1).withValues(alpha: (1.0 - p) * 0.1),
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
    canvas.drawPath(core, Paint()..color = bodyColor);

    // Fleece: layers of overlapping fluffy circles along the body
    final rng = Random(42); // deterministic fluff positions
    final fleeceColor = bodyColor;
    final lightFluff = _lighten(bodyColor, 0.06);
    final darkFluff = _darken(bodyColor, 0.04);

    // Outer fleece edge — big scallops along top & sides
    final scallops = [
      // Top row (back)
      [14.0, 36.0, 8.0], [24.0, 30.0, 9.0], [35.0, 28.0, 9.5],
      [46.0, 29.0, 9.0], [56.0, 31.0, 8.5], [66.0, 34.0, 8.0],
      // Left side (rump)
      [10.0, 48.0, 8.0], [8.0, 56.0, 7.5], [12.0, 64.0, 7.0],
      // Right side (chest)
      [74.0, 44.0, 7.0], [76.0, 54.0, 7.0], [74.0, 64.0, 6.5],
    ];
    for (final s in scallops) {
      final wobble = sin(phase * 3 * pi + s[0] * 0.2) * 0.5;
      canvas.drawCircle(
        Offset(s[0], s[1] + by + wobble),
        s[2],
        Paint()..color = fleeceColor,
      );
    }

    // Inner fleece detail — smaller puffs for texture
    for (int i = 0; i < 18; i++) {
      final fx = 16.0 + rng.nextDouble() * 56;
      final fy = 34.0 + rng.nextDouble() * 32;
      final fr = 3.5 + rng.nextDouble() * 3.5;
      final wobble = sin(phase * 4 * pi + i * 0.8) * 0.4;
      final c = i % 3 == 0 ? lightFluff : (i % 3 == 1 ? fleeceColor : darkFluff);
      canvas.drawCircle(Offset(fx, fy + by + wobble), fr, Paint()..color = c);
    }

    // White highlights on top
    for (int i = 0; i < 5; i++) {
      final hx = 22.0 + i * 10;
      final hy = 32.0 + by + sin(phase * 3 * pi + i) * 0.5;
      canvas.drawCircle(
        Offset(hx, hy),
        3.0 + rng.nextDouble() * 2,
        Paint()..color = Colors.white.withValues(alpha: 0.2),
      );
    }

    // Subtle outline
    canvas.drawPath(
      core,
      Paint()
        ..color = _darken(bodyColor, 0.18)
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
    canvas.drawPath(neck, Paint()..color = bodyColor);

    // Neck wool scallops along left edge (visible fluffy side)
    final neckFluff = [
      [62.0, 36.0, 6.0], [63.0, 28.0, 5.5], [65.0, 22.0, 5.0],
      [67.0, 16.0, 5.0], [70.0, 10.0, 4.5],
    ];
    for (final f in neckFluff) {
      final wobble = sin(phase * 3 * pi + f[1] * 0.3) * 0.4;
      canvas.drawCircle(
        Offset(f[0], f[1] + by * (f[1] / 40) + wobble),
        f[2],
        Paint()..color = bodyColor,
      );
    }

    // Right edge fluff (chest side)
    final chestFluff = [
      [80.0, 38.0, 5.0], [80.0, 30.0, 4.5], [80.0, 22.0, 4.0],
      [82.0, 14.0, 4.0],
    ];
    for (final f in chestFluff) {
      final wobble = sin(phase * 3 * pi + f[1] * 0.2 + 1) * 0.3;
      canvas.drawCircle(
        Offset(f[0], f[1] + by * (f[1] / 40) + wobble),
        f[2],
        Paint()..color = bodyColor,
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
        ..color = _darken(bodyColor, 0.18)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke,
    );
  }

  // ── HEAD: small, compact, elegant ──

  void _drawHead(Canvas canvas, double bounce) {
    final by = bounce * 0.2;
    final headColor = _darken(bodyColor, 0.05);
    final outlinePaint = Paint()
      ..color = _darken(bodyColor, 0.22)
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
      Paint()..color = _lighten(bodyColor, 0.08),
    );

    // Nostril
    canvas.drawCircle(
      Offset(95, 10 + by),
      0.8,
      Paint()..color = _darken(bodyColor, 0.4),
    );

    // Mouth line
    canvas.drawArc(
      Rect.fromCenter(center: Offset(93, 12 + by), width: 4, height: 2),
      0.2, 2.5, false,
      Paint()
        ..color = _darken(bodyColor, 0.25)
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
    canvas.drawPath(ear, Paint()..color = bodyColor);
    canvas.drawPath(ear, Paint()
      ..color = _darken(bodyColor, 0.2)
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
        Paint()..color = bodyColor,
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
      ..color = _darken(bodyColor, 0.12)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    final hoofPaint = Paint()..color = _darken(bodyColor, 0.35);
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
      ..color = _darken(bodyColor, 0.08)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    final hoofPaint = Paint()..color = _darken(bodyColor, 0.35);
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
      phase != old.phase || bodyColor != old.bodyColor;
}
