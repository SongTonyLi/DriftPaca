import 'package:flutter/material.dart';

abstract final class MotionDurations {
  static const quick = Duration(milliseconds: 200);
  static const standard = Duration(milliseconds: 300);
  static const emphasized = Duration(milliseconds: 400);
}

/// Depends on the `disableAnimations` aspect alone, so asking about the
/// preference does not also subscribe the caller to every unrelated MediaQuery
/// change (keyboard insets, rotation, brightness) and wake it on each of them.
bool animationsDisabled(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

Duration motionDuration(BuildContext context, Duration normal) =>
    animationsDisabled(context) ? Duration.zero : normal;
