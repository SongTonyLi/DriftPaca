import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Utils/perf_probe.dart';

void main() {
  group('PerfStats', () {
    test('aggregates frame timings in microseconds', () {
      final s = PerfStats();
      s.add(3000, 1000); // 3.0ms raster, 1.0ms build
      s.add(5000, 2000); // 5.0ms raster, 2.0ms build
      expect(s.frames, 2);
      expect(s.rasterSumMs, closeTo(8.0, 1e-9));
      expect(s.avgRasterMs, closeTo(4.0, 1e-9));
      expect(s.avgBuildMs, closeTo(1.5, 1e-9));
      expect(s.rasterMaxUs, 5000);
    });

    test('empty stats report zeros, not NaN', () {
      final s = PerfStats();
      expect(s.frames, 0);
      expect(s.avgRasterMs, 0);
      expect(s.rasterSumMs, 0);
    });

    test('reset clears all counters', () {
      final s = PerfStats()..add(1000, 1000);
      s.reset();
      expect(s.frames, 0);
      expect(s.rasterSumMs, 0);
      expect(s.rasterMaxUs, 0);
    });

    test('summary string includes frame count and sum', () {
      final s = PerfStats()..add(2000, 1000);
      final line = s.summary(const Duration(seconds: 30));
      expect(line, contains('frames=1'));
      expect(line, contains('30s'));
    });
  });
}
