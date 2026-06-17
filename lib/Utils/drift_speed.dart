import 'dart:math' as math;

/// Drift rate multiplier at rest (1.0 == the ~15s base loop).
const double kRestDriftSpeed = 1.0;

/// Drift rate multiplier while the assistant is generating ("slightly faster").
const double kGeneratingDriftSpeed = 1.4;

/// The speed the drift should ease toward, given generation state.
double targetDriftSpeed({required bool isGenerating}) =>
    isGenerating ? kGeneratingDriftSpeed : kRestDriftSpeed;

/// Exponentially ease [current] toward [target] over a frame of [dtSeconds].
/// [tau] is the time constant: ~63% of the remaining gap closes every [tau]
/// seconds, so the change is smooth and never overshoots. Returns [current]
/// unchanged when [dtSeconds] <= 0 (e.g. the first tick).
double easeDriftSpeed(double current, double target, double dtSeconds,
    {double tau = 0.18}) {
  if (dtSeconds <= 0) return current;
  final k = 1 - math.exp(-dtSeconds / tau);
  return current + (target - current) * k;
}
