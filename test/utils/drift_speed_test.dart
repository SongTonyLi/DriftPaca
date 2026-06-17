import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Utils/drift_speed.dart';

void main() {
  group('targetDriftSpeed', () {
    test('rest speed when idle', () {
      expect(targetDriftSpeed(isGenerating: false), kRestDriftSpeed);
    });
    test('faster when generating', () {
      expect(targetDriftSpeed(isGenerating: true), kGeneratingDriftSpeed);
      expect(kGeneratingDriftSpeed, greaterThan(kRestDriftSpeed));
    });
    test('eases to a standstill when inactive', () {
      expect(targetDriftSpeed(isGenerating: false, isActive: false),
          kIdleDriftSpeed);
      expect(kIdleDriftSpeed, 0.0);
    });
    test('inactive overrides generating', () {
      expect(targetDriftSpeed(isGenerating: true, isActive: false),
          kIdleDriftSpeed);
    });
    test('active + generating still fastest', () {
      expect(targetDriftSpeed(isGenerating: true, isActive: true),
          kGeneratingDriftSpeed);
    });
  });

  group('easeDriftSpeed', () {
    test('returns current unchanged for non-positive dt', () {
      expect(easeDriftSpeed(1.0, 1.4, 0.0), 1.0);
      expect(easeDriftSpeed(1.0, 1.4, -0.5), 1.0);
    });

    test('moves toward target without overshoot', () {
      final next = easeDriftSpeed(1.0, 1.4, 0.016);
      expect(next, greaterThan(1.0));
      expect(next, lessThan(1.4));
    });

    test('eases back down toward rest', () {
      final next = easeDriftSpeed(1.4, 1.0, 0.016);
      expect(next, lessThan(1.4));
      expect(next, greaterThan(1.0));
    });

    test('converges to target after enough steps', () {
      var s = 1.0;
      for (var i = 0; i < 600; i++) {
        s = easeDriftSpeed(s, 1.4, 0.016);
      }
      expect(s, closeTo(1.4, 0.001));
    });
  });
}
