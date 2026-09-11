import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Widgets/static_background.dart';

const _backgroundColor = Color(0xFFFAFAFA);

Widget _host() {
  return const SizedBox(
    width: 400,
    height: 800,
    child: StaticBackground(color: _backgroundColor),
  );
}

void main() {
  testWidgets('paints only the requested solid color', (tester) async {
    await tester.pumpWidget(_host());

    expect(find.byType(ColoredBox), findsOneWidget);
    final background = tester.widget<ColoredBox>(find.byType(ColoredBox));
    expect(background.color, _backgroundColor);
    expect(find.byType(CustomPaint), findsNothing);
  });

  testWidgets('never schedules background animation frames', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump(const Duration(seconds: 1));

    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}
