import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Widgets/floating_gradient_background.dart';
import 'package:llamaseek/Widgets/gradient/mesh_geometry.dart';

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

/// The welcome screen as the app hosts it: a full MediaQuery above the
/// background, so a test can move an unrelated bit of it (the keyboard inset).
Widget _welcomeHost({
  bool generating = false,
  bool welcome = true,
  EdgeInsets viewInsets = EdgeInsets.zero,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: const Size(400, 800), viewInsets: viewInsets),
      child: FloatingGradientBackground(
        meshA: const Color(0xFF4FB4FF),
        meshB: const Color(0xFFFF73B3),
        canvas: const Color(0xFFF4E9FF),
        idleColor: const Color(0xFFFFFFFF),
        isGenerating: generating,
        isWelcome: welcome,
      ),
    ),
  );
}

/// The live [Mesh] the painter reads, so a test can watch what is actually being
/// drawn (which field, at what opacity) frame by frame.
Mesh _meshOf(WidgetTester tester) {
  final paint = tester
      .widgetList<CustomPaint>(find.descendant(
        of: find.byType(FloatingGradientBackground),
        matching: find.byType(CustomPaint),
      ))
      .first;
  return (paint.painter as dynamic).mesh as Mesh;
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
    await tester.pump(const Duration(seconds: 6)); // fade fully in (clamped at 1.0)
    await tester.pumpWidget(_host(generating: false));
    // Fade-out is ~8s; pump well past it so opacity reaches 0 and the ticker stops.
    await tester.pump(const Duration(seconds: 10));
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

  testWidgets('welcome intro plays once and then settles to a flat idle',
      (tester) async {
    await tester.pumpWidget(_welcomeHost());
    final mesh = _meshOf(tester);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(mesh.welcome, isTrue, reason: 'the intro should be on screen');
    expect(mesh.opacity, greaterThan(0.0));

    await tester.pumpAndSettle();
    expect(mesh.opacity, lessThan(0.01));
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: 'the intro is one-shot; the ticker must stop afterwards');
  });

  testWidgets('an unrelated MediaQuery change does not replay the welcome intro',
      (tester) async {
    await tester.pumpWidget(_welcomeHost());
    await tester.pumpAndSettle(); // intro plays out, ticker stops
    expect(tester.binding.hasScheduledFrame, isFalse);

    // Opening the keyboard changes MediaQuery.viewInsets — nothing to do with
    // the background, and it must not restart the intro.
    await tester
        .pumpWidget(_welcomeHost(viewInsets: const EdgeInsets.only(bottom: 320)));
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: 'showing the keyboard must not replay the welcome intro');
  });

  testWidgets('generation takes over the intro without a visible field swap',
      (tester) async {
    await tester.pumpWidget(_welcomeHost());
    final mesh = _meshOf(tester);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(mesh.welcome, isTrue);
    expect(mesh.opacity, greaterThan(0.5), reason: 'intro should be visible');

    // Sending the first message: welcome ends, generation starts. The corner
    // field and the drifting mesh are different pictures, so swapping between
    // them while either is visible reads as a flicker.
    await tester.pumpWidget(_welcomeHost(generating: true, welcome: false));
    var wasWelcome = mesh.welcome;
    double? swapOpacity;
    for (var i = 0; i < 60 && swapOpacity == null; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (mesh.welcome != wasWelcome) swapOpacity = mesh.opacity;
      wasWelcome = mesh.welcome;
    }
    expect(swapOpacity, isNotNull, reason: 'should hand over to the mesh');
    expect(swapOpacity, lessThan(0.02),
        reason: 'the field may only change while it is invisible');
  });

  testWidgets('reduced motion paints generation without scheduling frames',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: FloatingGradientBackground(
            meshA: Color(0xFF4FB4FF),
            meshB: Color(0xFFFF73B3),
            canvas: Color(0xFFF4E9FF),
            idleColor: Color(0xFFFFFFFF),
            isGenerating: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
