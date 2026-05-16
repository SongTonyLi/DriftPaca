import 'dart:math';
import 'package:flutter/material.dart';

/// A tiny animated llama that runs inline at the end of streaming text,
/// then rests when generation is complete.
class StreamingLlama extends StatefulWidget {
  final bool isRunning;

  const StreamingLlama({super.key, this.isRunning = true});

  @override
  State<StreamingLlama> createState() => _StreamingLlamaState();
}

class _StreamingLlamaState extends State<StreamingLlama>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.isRunning ? 350 : 2000),
    )..repeat();
  }

  @override
  void didUpdateWidget(StreamingLlama old) {
    super.didUpdateWidget(old);
    if (widget.isRunning != old.isRunning) {
      _controller.duration =
          Duration(milliseconds: widget.isRunning ? 350 : 2000);
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: const Size(28, 18),
          painter: _LlamaPainter(
            phase: _controller.value,
            isRunning: widget.isRunning,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        );
      },
    );
  }
}

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
    final fill = Paint()..color = color;
    final bounce = isRunning ? sin(phase * 2 * pi) * 1.4 : 0.0;
    final breathe = !isRunning ? sin(phase * 2 * pi) * 0.3 : 0.0;
    final by = bounce + breathe; // combined vertical offset

    // ── dust particles (running only) ──
    if (isRunning) {
      for (int i = 0; i < 3; i++) {
        final p = (phase + i * 0.33) % 1.0;
        canvas.drawCircle(
          Offset(6 - p * 9, 14.5 + by + p * 2),
          0.5 + p * 1.1,
          Paint()..color = color.withValues(alpha: (1.0 - p) * 0.22),
        );
      }
    }

    // ── body ──
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(6, 8 + by, 11, 4.8),
        const Radius.circular(2.4),
      ),
      fill,
    );

    // ── neck ──
    final neck = Path()
      ..moveTo(15.5, 8.5 + by)
      ..quadraticBezierTo(17, 5.5 + by, 18, 4 + by);
    canvas.drawPath(
      neck,
      Paint()
        ..color = color
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );

    // ── head ──
    canvas.drawOval(
      Rect.fromCenter(center: Offset(19.5, 3 + by), width: 5, height: 3.6),
      fill,
    );

    // ── ears ──
    final ear = Paint()
      ..color = color
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(18.2, 1.5 + by), Offset(17.6, 0 + by), ear);
    canvas.drawLine(Offset(20.5, 1 + by), Offset(21, -0.5 + by), ear);

    // ── eye ──
    if (isRunning) {
      canvas.drawCircle(
        Offset(21, 2.7 + by),
        0.7,
        Paint()..color = Colors.white.withValues(alpha: 0.75),
      );
    } else {
      // resting: happy squint
      canvas.drawLine(
        Offset(20.3, 2.8 + by),
        Offset(21.5, 2.5 + by),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.55)
          ..strokeWidth = 0.7
          ..strokeCap = StrokeCap.round,
      );
    }

    // ── legs ──
    final leg = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    const footY = 17.0;

    if (isRunning) {
      final lp = phase * 2 * pi;
      _leg(canvas, 15, 12.5 + by, sin(lp) * 3.5, footY, leg);
      _leg(canvas, 13.2, 12.5 + by, sin(lp + pi) * 3.5, footY, leg);
      _leg(canvas, 9.5, 12.5 + by, sin(lp + pi * 0.6) * 3, footY, leg);
      _leg(canvas, 7.8, 12.5 + by, sin(lp + pi * 1.6) * 3, footY, leg);
    } else {
      _leg(canvas, 15, 12.5 + by, 0, footY, leg);
      _leg(canvas, 13.2, 12.5 + by, 0, footY, leg);
      _leg(canvas, 9.5, 12.5 + by, 0, footY, leg);
      _leg(canvas, 7.8, 12.5 + by, 0, footY, leg);
    }

    // ── tail ──
    final tailWag = isRunning ? sin(phase * 4 * pi) * 2.5 : sin(phase * 2 * pi) * 0.5;
    final tail = Path()
      ..moveTo(6, 9.5 + by)
      ..quadraticBezierTo(3.5, 7 + by + tailWag, 2.5, 8.5 + by + tailWag * 0.4);
    canvas.drawPath(
      tail,
      Paint()
        ..color = color
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  void _leg(Canvas canvas, double x, double top, double offset, double foot, Paint p) {
    canvas.drawLine(Offset(x, top), Offset(x + offset, foot), p);
  }

  @override
  bool shouldRepaint(_LlamaPainter old) =>
      phase != old.phase || isRunning != old.isRunning || color != old.color;
}
