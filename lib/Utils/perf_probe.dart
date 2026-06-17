import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Compile-time flag: pass `--dart-define=PERF_PROBE=true` to enable the HUD.
const bool kPerfProbe = bool.fromEnvironment('PERF_PROBE');

/// Pure rolling aggregate of frame raster/build times (input in microseconds).
class PerfStats {
  int frames = 0;
  int rasterSumUs = 0;
  int buildSumUs = 0;
  int rasterMaxUs = 0;

  void add(int rasterUs, int buildUs) {
    frames++;
    rasterSumUs += rasterUs;
    buildSumUs += buildUs;
    if (rasterUs > rasterMaxUs) rasterMaxUs = rasterUs;
  }

  void reset() {
    frames = 0;
    rasterSumUs = 0;
    buildSumUs = 0;
    rasterMaxUs = 0;
  }

  double get avgRasterMs => frames == 0 ? 0 : (rasterSumUs / frames) / 1000;
  double get avgBuildMs => frames == 0 ? 0 : (buildSumUs / frames) / 1000;
  double get rasterSumMs => rasterSumUs / 1000;

  String summary(Duration window) =>
      'PerfProbe[${window.inSeconds}s]: frames=$frames '
      'Sum_raster=${rasterSumMs.toStringAsFixed(1)}ms '
      'avg_raster=${avgRasterMs.toStringAsFixed(2)}ms '
      'max_raster=${(rasterMaxUs / 1000).toStringAsFixed(2)}ms '
      'avg_build=${avgBuildMs.toStringAsFixed(2)}ms';
}

/// Wraps [child] with a small on-screen readout of rendering cost and prints a
/// summary line to the console every [window]. Enable only via [kPerfProbe].
class PerfProbeHud extends StatefulWidget {
  final Widget child;
  final Duration window;
  const PerfProbeHud({
    super.key,
    required this.child,
    this.window = const Duration(seconds: 30),
  });

  @override
  State<PerfProbeHud> createState() => _PerfProbeHudState();
}

class _PerfProbeHudState extends State<PerfProbeHud> {
  final PerfStats _stats = PerfStats();
  final Stopwatch _sw = Stopwatch();
  Timer? _ui;
  String _line = 'PerfProbe: warming up...';

  @override
  void initState() {
    super.initState();
    _sw.start();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _ui = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _line = 'frames=${_stats.frames}  '
          'avgR=${_stats.avgRasterMs.toStringAsFixed(2)}ms  '
          'SumR=${_stats.rasterSumMs.toStringAsFixed(0)}ms');
    });
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _stats.add(t.rasterDuration.inMicroseconds, t.buildDuration.inMicroseconds);
    }
    if (_sw.elapsed >= widget.window) {
      debugPrint(_stats.summary(_sw.elapsed));
      _stats.reset();
      _sw
        ..reset()
        ..start();
    }
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _ui?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 44,
          left: 8,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              color: const Color(0xAA000000),
              child: Text(
                _line,
                style: const TextStyle(
                  color: Color(0xFF00FF88),
                  fontSize: 11,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
