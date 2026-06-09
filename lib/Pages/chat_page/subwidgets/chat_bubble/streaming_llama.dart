import 'dart:math';
import 'package:flutter/material.dart';

/// A tiny animated llama that runs while streaming, then winds down through
/// idle behaviors (eating grass, looking around) and falls asleep.
class StreamingLlama extends StatefulWidget {
  final bool isRunning;

  const StreamingLlama({super.key, this.isRunning = true});

  @override
  State<StreamingLlama> createState() => _StreamingLlamaState();
}

class _StreamingLlamaState extends State<StreamingLlama>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _controller;

  // Where the idle play-through settles: mid-sleep, so the final frozen
  // frame shows a closed eye and zzz particles. Stopping (rather than
  // looping) releases the ticker — a resting llama costs no frames, which
  // matters because this widget stays in the bubble after streaming ends.
  static const double _sleepPhase = 0.8;
  static const Duration _runCycle = Duration(milliseconds: 300);
  static const Duration _idleCycle = Duration(milliseconds: 12000);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(vsync: this);
    _applyMode();
  }

  /// Running loops the gait cycle; idle plays eat → look → sleep once and
  /// stops at [_sleepPhase].
  void _applyMode() {
    if (widget.isRunning) {
      _controller.duration = _runCycle;
      _controller.repeat();
    } else {
      _controller.duration = _idleCycle;
      _controller.value = 0.0;
      _controller.animateTo(_sleepPhase);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _controller.stop();
    } else if (state == AppLifecycleState.resumed) {
      if (widget.isRunning) {
        _controller.repeat();
      } else if (_controller.value < _sleepPhase) {
        _controller.animateTo(_sleepPhase);
      }
    }
  }

  @override
  void didUpdateWidget(StreamingLlama old) {
    super.didUpdateWidget(old);
    if (widget.isRunning != old.isRunning) {
      _applyMode();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: const Size(24, 18),
          painter: _LlamaPainter(
            phase: _controller.value,
            isRunning: widget.isRunning,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.45),
          ),
        );
      },
    );
  }
}

// ─── idle behavior phases within the 12-second cycle ───
// 0.00–0.28  eating grass
// 0.28–0.33  transition → looking around
// 0.33–0.61  looking around / resting
// 0.61–0.66  transition → sleeping
// 0.66–0.95  sleeping
// 0.95–1.00  transition → eating (loop)

class _LlamaPainter extends CustomPainter {
  final double phase;
  final bool isRunning;
  final Color color;

  _LlamaPainter({
    required this.phase,
    required this.isRunning,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (isRunning) {
      _paintRunning(canvas);
    } else {
      _paintIdle(canvas);
    }
  }

  // ════════════════════════════════════════════
  //  RUNNING
  // ════════════════════════════════════════════

  void _paintRunning(Canvas canvas) {
    final fill = Paint()..color = color;
    final by = sin(phase * 2 * pi) * 1.2;

    // dust
    for (int i = 0; i < 3; i++) {
      final p = (phase + i * 0.33) % 1.0;
      canvas.drawCircle(
        Offset(4 - p * 7, 14 + by + p * 1.5),
        0.5 + p * 0.9,
        Paint()..color = color.withValues(alpha: (1.0 - p) * 0.2),
      );
    }

    _drawBody(canvas, fill, by);
    _drawNeck(canvas, by, 0);
    _drawHead(canvas, by, 0);
    _drawEars(canvas, by, 0);

    // open eye
    canvas.drawCircle(
      Offset(17.5, 2.8 + by),
      0.7,
      Paint()..color = Colors.white.withValues(alpha: 0.7),
    );

    // running legs
    final leg = _legPaint;
    final lp = phase * 2 * pi;
    _leg(canvas, 12, 10.5 + by, sin(lp) * 2.8, 15.5, leg);
    _leg(canvas, 10.5, 10.5 + by, sin(lp + pi) * 2.8, 15.5, leg);
    _leg(canvas, 7, 10.5 + by, sin(lp + pi * 0.6) * 2.5, 15.5, leg);
    _leg(canvas, 5.5, 10.5 + by, sin(lp + pi * 1.6) * 2.5, 15.5, leg);

    // tail wag
    canvas.drawCircle(
      Offset(3.5, 6.5 + by + sin(phase * 4 * pi) * 0.5),
      1.5,
      Paint()..color = color.withValues(alpha: 0.6),
    );
  }

  // ════════════════════════════════════════════
  //  IDLE (eating → looking around → sleeping)
  // ════════════════════════════════════════════

  void _paintIdle(Canvas canvas) {
    final fill = Paint()..color = color;

    // Compute smooth blended parameters across the cycle
    final headDip = _headDip();
    final sleepDrop = _sleepDrop();
    final breathe = sin(phase * 12 * pi) * 0.25; // constant gentle breathing
    final by = breathe - sleepDrop;

    // grass tufts (visible during eating)
    final grassAlpha = _grassAlpha();
    if (grassAlpha > 0.01) {
      _drawGrass(canvas, by, grassAlpha);
    }

    _drawBody(canvas, fill, by);
    _drawNeck(canvas, by, headDip);
    _drawHead(canvas, by, headDip);
    _drawEars(canvas, by, headDip);

    // eye depends on state
    if (_isSleeping()) {
      _drawClosedEye(canvas, by, headDip);
    } else if (_isEating()) {
      _drawOpenEye(canvas, by, headDip);
    } else {
      // looking around — eye with slight head turn
      _drawOpenEye(canvas, by, headDip);
    }

    // standing/tucked legs
    final footY = 15.5 + sleepDrop * 0.5;
    final leg = _legPaint;
    _leg(canvas, 12, 10.5 + by, 0, footY, leg);
    _leg(canvas, 10.5, 10.5 + by, 0, footY, leg);
    _leg(canvas, 7, 10.5 + by, 0, footY, leg);
    _leg(canvas, 5.5, 10.5 + by, 0, footY, leg);

    // tail
    final tailSway = sin(phase * 6 * pi) * 0.3;
    canvas.drawCircle(
      Offset(3.5, 6.5 + by + tailSway),
      1.5,
      Paint()..color = color.withValues(alpha: 0.6),
    );

    // zzz particles (sleeping)
    final zzzAlpha = _zzzAlpha();
    if (zzzAlpha > 0.01) {
      _drawZzz(canvas, by, headDip, zzzAlpha);
    }
  }

  // ── idle state helpers ──

  bool _isEating() => phase < 0.28;
  bool _isSleeping() => phase > 0.66 && phase < 0.95;

  /// Head dips down during eating (0.0–0.28), with chomping oscillation.
  double _headDip() {
    if (phase < 0.28) {
      final local = phase / 0.28;
      return 3.0 + sin(local * 8 * pi) * 0.8; // dip + chomp
    } else if (phase < 0.33) {
      return 3.0 * (1.0 - (phase - 0.28) / 0.05); // rise back up
    } else if (phase > 0.95) {
      return 3.0 * ((phase - 0.95) / 0.05); // dip for next eating
    }
    return 0;
  }

  /// Body settles lower during sleeping (0.66–0.95).
  double _sleepDrop() {
    if (phase > 0.66 && phase < 0.95) {
      return 0.8;
    } else if (phase > 0.61 && phase <= 0.66) {
      return 0.8 * ((phase - 0.61) / 0.05);
    } else if (phase >= 0.95) {
      return 0.8 * (1.0 - (phase - 0.95) / 0.05);
    }
    return 0;
  }

  /// Grass visibility: full during eating, fades at transition.
  double _grassAlpha() {
    if (phase < 0.25) return 0.35;
    if (phase < 0.33) return 0.35 * (1.0 - (phase - 0.25) / 0.08);
    if (phase > 0.95) return 0.35 * ((phase - 0.95) / 0.05);
    return 0;
  }

  /// Zzz visibility during sleeping.
  double _zzzAlpha() {
    if (phase > 0.70 && phase < 0.90) return 0.35;
    if (phase >= 0.66 && phase <= 0.70) return 0.35 * ((phase - 0.66) / 0.04);
    if (phase >= 0.90 && phase <= 0.95) return 0.35 * (1.0 - (phase - 0.90) / 0.05);
    return 0;
  }

  // ── shared drawing helpers ──

  void _drawBody(Canvas canvas, Paint fill, double by) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(4, 5.5 + by, 10, 5.5),
        const Radius.circular(2.8),
      ),
      fill,
    );
  }

  void _drawNeck(Canvas canvas, double by, double headDip) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(12.5, 3.5 + by + headDip * 0.4, 2.8, 4),
        const Radius.circular(1.4),
      ),
      Paint()..color = color,
    );
  }

  void _drawHead(Canvas canvas, double by, double headDip) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(16, 3 + by + headDip),
        width: 5,
        height: 4.2,
      ),
      Paint()..color = color,
    );
  }

  void _drawEars(Canvas canvas, double by, double headDip) {
    final ear = Paint()
      ..color = color
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final dy = by + headDip;
    canvas.drawPath(
      Path()
        ..moveTo(14.8, 1.5 + dy)
        ..quadraticBezierTo(14.2, -0.5 + dy, 14.8, -0.2 + dy),
      ear,
    );
    canvas.drawPath(
      Path()
        ..moveTo(16.8, 1 + dy)
        ..quadraticBezierTo(17.2, -1 + dy, 17.8, -0.2 + dy),
      ear,
    );
  }

  void _drawOpenEye(Canvas canvas, double by, double headDip) {
    canvas.drawCircle(
      Offset(17.5, 2.8 + by + headDip),
      0.7,
      Paint()..color = Colors.white.withValues(alpha: 0.7),
    );
  }

  void _drawClosedEye(Canvas canvas, double by, double headDip) {
    final ey = 3.0 + by + headDip;
    canvas.drawPath(
      Path()
        ..moveTo(16.8, ey)
        ..quadraticBezierTo(17.5, ey - 0.5, 18.2, ey),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..strokeWidth = 0.7
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawGrass(Canvas canvas, double by, double alpha) {
    final gp = Paint()
      ..color = Color(0xFF6DB36D).withValues(alpha: alpha)
      ..strokeWidth = 0.9
      ..strokeCap = StrokeCap.round;
    final gx = 17.0;
    final gy = 8.5 + by;
    canvas.drawLine(Offset(gx - 1.5, gy), Offset(gx - 2.5, gy - 2), gp);
    canvas.drawLine(Offset(gx, gy), Offset(gx, gy - 2.5), gp);
    canvas.drawLine(Offset(gx + 1.5, gy), Offset(gx + 2.5, gy - 2), gp);
  }

  void _drawZzz(Canvas canvas, double by, double headDip, double alpha) {
    final zPaint = Paint()
      ..color = color.withValues(alpha: alpha)
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Two floating z's at different heights, drifting upward
    final drift = sin(phase * 8 * pi) * 0.5;
    final baseX = 19.5;
    final baseY = -0.5 + by + headDip;

    _zShape(canvas, Offset(baseX, baseY + drift), 2.0, zPaint);
    _zShape(canvas, Offset(baseX + 2.5, baseY - 2 - drift * 0.5), 1.5,
        zPaint..color = color.withValues(alpha: alpha * 0.6));
  }

  void _zShape(Canvas canvas, Offset pos, double s, Paint paint) {
    canvas.drawLine(pos, Offset(pos.dx + s, pos.dy), paint);
    canvas.drawLine(
        Offset(pos.dx + s, pos.dy), Offset(pos.dx, pos.dy + s), paint);
    canvas.drawLine(
        Offset(pos.dx, pos.dy + s), Offset(pos.dx + s, pos.dy + s), paint);
  }

  Paint get _legPaint => Paint()
    ..color = color
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round;

  void _leg(
      Canvas c, double x, double top, double off, double foot, Paint p) {
    c.drawLine(Offset(x, top), Offset(x + off, foot), p);
  }

  @override
  bool shouldRepaint(_LlamaPainter old) =>
      phase != old.phase || isRunning != old.isRunning || color != old.color;
}
