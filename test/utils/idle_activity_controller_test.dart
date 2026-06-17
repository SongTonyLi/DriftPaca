import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Utils/idle_activity_controller.dart';

void main() {
  // A controllable fake timer: capture the most recent idle callback so the
  // test can fire it deterministically.
  late void Function() fireIdle;
  IdleActivityController build() => IdleActivityController(
        createTimer: (d, cb) {
          fireIdle = cb;
          return Timer(const Duration(days: 1), () {});
        },
      );

  test('starts active', () {
    final c = build();
    addTearDown(c.dispose);
    expect(c.isActive, isTrue);
  });

  test('goes inactive when the idle timer fires, notifying once', () {
    final c = build();
    addTearDown(c.dispose);
    var notifies = 0;
    c.addListener(() => notifies++);

    fireIdle();
    expect(c.isActive, isFalse);
    expect(notifies, 1);
  });

  test('poke after idle returns to active and notifies', () {
    final c = build();
    addTearDown(c.dispose);
    fireIdle();
    var notifies = 0;
    c.addListener(() => notifies++);

    c.poke();
    expect(c.isActive, isTrue);
    expect(notifies, 1);
  });

  test('poke while active does NOT notify (no rebuild spam)', () {
    final c = build();
    addTearDown(c.dispose);
    var notifies = 0;
    c.addListener(() => notifies++);

    c.poke();
    c.poke();
    expect(c.isActive, isTrue);
    expect(notifies, 0);
  });

  test('poke re-arms the idle timer (a later fire still works)', () {
    final c = build();
    addTearDown(c.dispose);
    c.poke(); // re-arms; fireIdle now points at the fresh timer's callback
    fireIdle();
    expect(c.isActive, isFalse);
  });
}
