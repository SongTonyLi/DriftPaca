import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
