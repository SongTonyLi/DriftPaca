import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Widgets/floating_gradient_background.dart';

Widget _host({required bool generating}) {
  return MaterialApp(
    home: SizedBox(
      width: 400,
      height: 800,
      child: FloatingGradientBackground(
        meshA: const Color(0xFF4FB4FF),
        meshB: const Color(0xFFFF73B3),
        canvas: const Color(0xFFF4E9FF),
        idleColor: const Color(0xFFFFFFFF),
        isGenerating: generating,
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

  testWidgets('idle (not generating) schedules no frames', (tester) async {
    await tester.pumpWidget(_host(generating: false));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: 'a flat idle background must not animate');
    expect(tester.takeException(), isNull);
  });

  testWidgets('generation wakes the ticker to fade the mesh in', (tester) async {
    await tester.pumpWidget(_host(generating: false));
    await tester.pump(const Duration(seconds: 1)); // settle to idle
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(_host(generating: true));
    await tester.pump(); // process the start
    expect(tester.binding.hasScheduledFrame, isTrue,
        reason: 'generation should start animating');
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('stops animating once faded out after generation ends',
      (tester) async {
    await tester.pumpWidget(_host(generating: true));
    await tester.pump(const Duration(seconds: 3)); // fade in
    await tester.pumpWidget(_host(generating: false));
    // Fade-out is ~4s; pump well past it so opacity reaches 0 and the ticker stops.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: 'ticker should stop once the mesh has faded out');
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposes its ticker cleanly while animating', (tester) async {
    await tester.pumpWidget(_host(generating: true));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
