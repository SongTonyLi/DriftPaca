import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:llamaseek/Utils/idle_activity_controller.dart';
import 'package:llamaseek/Widgets/idle_activity_detector.dart';

void main() {
  testWidgets('a pointer down pokes the ambient controller', (tester) async {
    late void Function() fireIdle;
    final c = IdleActivityController(createTimer: (d, cb) {
      fireIdle = cb;
      return Timer(const Duration(days: 1), () {});
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<IdleActivityController>.value(
        value: c,
        child: const MaterialApp(
          home: IdleActivityDetector(child: SizedBox.expand()),
        ),
      ),
    );

    fireIdle(); // force idle
    expect(c.isActive, isFalse);

    await tester.tap(find.byType(IdleActivityDetector));
    expect(c.isActive, isTrue, reason: 'tap should poke the controller');

    // Dispose inside the body so the controller's pending idle timer is
    // cancelled before the widget binding's end-of-test timer check.
    c.dispose();
  });
}
