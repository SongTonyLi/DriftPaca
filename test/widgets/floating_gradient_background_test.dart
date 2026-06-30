import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Records every `HapticFeedback.*` the widget fires, by intercepting the
/// platform channel they all funnel through. Returns the (live) list of the
/// `HapticFeedbackType.*` argument strings, in order.
List<String> _recordHaptics(WidgetTester tester) {
  final calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add(call.arguments as String? ?? 'vibrate');
      }
      return null;
    },
  );
  return calls;
}

/// Pumps [total] in small [step]s so the per-frame `dt` stays realistic — a
/// single giant pump would collapse many beats into one frame.
Future<void> _pumpFor(
  WidgetTester tester,
  Duration total, {
  Duration step = const Duration(milliseconds: 200),
}) async {
  var elapsed = Duration.zero;
  while (elapsed < total) {
    await tester.pump(step);
    elapsed += step;
  }
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

  testWidgets('generating emits slow, soft haptic beats in time with the drift',
      (tester) async {
    final haptics = _recordHaptics(tester);
    await tester.pumpWidget(_host(generating: true));
    await tester.pump(); // process the start
    await _pumpFor(tester, const Duration(seconds: 15));

    expect(haptics, isNotEmpty,
        reason: 'a generating mesh should beat in time with the blobs');
    expect(haptics.every((h) => h == 'HapticFeedbackType.lightImpact'), isTrue,
        reason: 'the beat is a soft light impact');
    // ~4s/beat → only a handful over 15s. The upper bound guards the "slow"
    // intent: a fast metronome — or a per-frame bug — would fire far more.
    expect(haptics.length, lessThan(8),
        reason: 'the beat must stay a slow rhythm, not a buzz');
    expect(tester.takeException(), isNull);
  });

  testWidgets('idle (not generating) never beats', (tester) async {
    final haptics = _recordHaptics(tester);
    await tester.pumpWidget(_host(generating: false));
    await _pumpFor(tester, const Duration(seconds: 15));
    expect(haptics, isEmpty, reason: 'a flat idle background must not buzz');
  });

  testWidgets(
      'beats stop the instant generation ends, even as the mesh fades out',
      (tester) async {
    final haptics = _recordHaptics(tester);
    await tester.pumpWidget(_host(generating: true));
    await tester.pump();
    await _pumpFor(tester, const Duration(seconds: 10)); // collect some beats
    expect(haptics, isNotEmpty);

    await tester.pumpWidget(_host(generating: false));
    haptics.clear();
    // The ticker keeps running for the ~3s fade-out, but the beat is gated to
    // isGenerating — so no further pulses should fire while it fades.
    await _pumpFor(tester, const Duration(seconds: 5));
    expect(haptics, isEmpty,
        reason: 'haptics are gated to isGenerating, not merely to the ticker');
  });
}
