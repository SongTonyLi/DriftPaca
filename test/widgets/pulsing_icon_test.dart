import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Widgets/pulsing_icon.dart';

Widget host({required bool disabled}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disabled),
        child: const Scaffold(
          body: PulsingIcon(
            icon: Icons.auto_awesome,
            size: 20,
            color: Colors.blue,
          ),
        ),
      ),
    );

void main() {
  testWidgets('pulses while motion is enabled', (tester) async {
    await tester.pumpWidget(host(disabled: false));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('renders static while motion is disabled', (tester) async {
    await tester.pumpWidget(host(disabled: true));
    await tester.pump();

    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
