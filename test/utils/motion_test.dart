import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Utils/motion.dart';

void main() {
  testWidgets('motionDuration preserves normal timing', (tester) async {
    late Duration resolved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            resolved = motionDuration(context, MotionDurations.standard);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(resolved, MotionDurations.standard);
  });

  testWidgets(
      'motionDuration settles immediately when animations are disabled',
      (tester) async {
    late Duration resolved;
    late bool disabled;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              disabled = animationsDisabled(context);
              resolved = motionDuration(context, MotionDurations.emphasized);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(disabled, isTrue);
    expect(resolved, Duration.zero);
  });
}
