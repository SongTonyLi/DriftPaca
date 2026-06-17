import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Utils/idle_activity_controller.dart';
import 'package:llamaseek/Widgets/floating_gradient_background.dart';

Widget _host({required bool generating, Color a = const Color(0xFF4FB4FF),
    Color b = const Color(0xFFFF73B3), Color canvas = const Color(0xFFF4E9FF)}) {
  return MaterialApp(
    home: SizedBox(
      width: 400,
      height: 800,
      child: FloatingGradientBackground(
        meshA: a, meshB: b, canvas: canvas, isGenerating: generating,
      ),
    ),
  );
}

void main() {
  testWidgets('builds and paints', (tester) async {
    await tester.pumpWidget(_host(generating: false));
    expect(find.byType(FloatingGradientBackground), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('advances frames without error', (tester) async {
    await tester.pumpWidget(_host(generating: false));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives generation + color changes', (tester) async {
    await tester.pumpWidget(_host(generating: false));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(_host(generating: true, a: const Color(0xFF7C5CFF)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposes its ticker cleanly', (tester) async {
    await tester.pumpWidget(_host(generating: true));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('stops scheduling frames after idle, resumes on poke',
      (tester) async {
    final c = IdleActivityController(idleAfter: const Duration(seconds: 4));
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 400,
        height: 800,
        child: FloatingGradientBackground(
          meshA: const Color(0xFF4FB4FF),
          meshB: const Color(0xFFFF73B3),
          canvas: const Color(0xFFF4E9FF),
          isGenerating: false,
          activity: c,
        ),
      ),
    ));

    // Run, then let the 4s idle timer fire and the ~1s ease-to-freeze settle.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 2));
    expect(c.isActive, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: 'ticker should be stopped while idle');

    // Activity resumes animation.
    c.poke();
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue,
        reason: 'ticker should restart on poke');
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);

    // Drain the re-armed idle timer so it fires (and refreezes) within the
    // test rather than outliving the widget tree.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 2));
    expect(c.isActive, isFalse);
  });

  testWidgets('keeps animating while generating even if idle fires',
      (tester) async {
    final c = IdleActivityController(idleAfter: const Duration(seconds: 4));
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 400,
        height: 800,
        child: FloatingGradientBackground(
          meshA: const Color(0xFF4FB4FF),
          meshB: const Color(0xFFFF73B3),
          canvas: const Color(0xFFF4E9FF),
          isGenerating: true,
          activity: c,
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.hasScheduledFrame, isTrue,
        reason: 'generation keeps the ticker running');
  });
}
