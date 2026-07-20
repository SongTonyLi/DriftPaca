import 'package:flutter/material.dart';

abstract final class MotionDurations {
  static const quick = Duration(milliseconds: 200);
  static const standard = Duration(milliseconds: 300);
  static const emphasized = Duration(milliseconds: 400);
}

bool animationsDisabled(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

Duration motionDuration(BuildContext context, Duration normal) =>
    animationsDisabled(context) ? Duration.zero : normal;
