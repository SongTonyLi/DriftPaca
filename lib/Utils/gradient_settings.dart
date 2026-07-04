import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:llamaseek/Constants/gradient_presets.dart';

const String kBgColor1Key = 'bgColor1';
const String kBgColor2Key = 'bgColor2';
const String kLegacyAccentKey = 'color';

/// Read the active gradient pair from [box]. Colors are stored as ARGB ints.
/// Falls back to the legacy single-accent color (migration), then to the
/// default preset.
GradientPair readGradientPair(Box box) {
  final v1 = box.get(kBgColor1Key);
  final v2 = box.get(kBgColor2Key);
  if (v1 is int && v2 is int) {
    return GradientPair(Color(v1), Color(v2));
  }
  final legacy = box.get(kLegacyAccentKey);
  if (legacy is Color) {
    return GradientPair(Color(legacy.toARGB32()), kGradientPresets.first.c2);
  }
  return kGradientPresets.first;
}

/// Persist [pair] as ARGB ints under the bgColor keys.
void writeGradientPair(Box box, GradientPair pair) {
  box.put(kBgColor1Key, pair.c1.toARGB32());
  box.put(kBgColor2Key, pair.c2.toARGB32());
}
