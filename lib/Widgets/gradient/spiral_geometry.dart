import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Mutable per-frame values the painter reads. [phase] advances continuously;
/// [opacity] (0..1) fades the whole field in/out over the flat idle background.
class SpiralField {
  double phase = 0;
  double opacity = 0; // 0 = hidden (flat idle bg), 1 = full field
  Color a = const Color(0xFF000000);
  Color b = const Color(0xFF000000);
  Color canvas = const Color(0xFF000000);
  bool welcome = false; // true during the quiet welcome intro
}

/// The `uniform vec4` declarations of shaders/halftone_spiral.frag, in order.
/// [buildSpiralUniforms] packs one vec4 (four floats) per entry, in this order;
/// a test checks the shader source declares exactly this sequence.
const List<String> kSpiralUniformOrder = [
  'uIdle',
  'uCanvas',
  'uColA',
  'uColB',
  'uStar',
  'uSpiral',
  'uFlow',
  'uField',
  'uTwinkle',
];

/// Floats in the uniform buffer: one vec4 per [kSpiralUniformOrder] entry.
const int kSpiralUniformFloats = 4 * 9;

/// Where the spiral's core sits at rest, as a fraction of the canvas: a little
/// above centre, where the eye rests on a chat screen.
const Offset kSpiralAnchor = Offset(0.5, 0.44);

/// How far the core floats around its anchor (fraction of the short side).
const double kSpiralDriftAmt = 0.06;

/// Radial gap between neighbouring arms, as a fraction of the short side,
/// clamped so a watch-sized or a desktop-sized canvas both get a readable
/// number of halftone dots per arm.
const double kSpiralPitchFrac = 0.17;
const double kSpiralPitchMin = 44.0;
const double kSpiralPitchMax = 132.0;

/// Outer radius of the field as a fraction of the canvas diagonal. Large
/// enough that, wherever the core has floated to, every corner is still inside
/// the field (the arms thin out towards this edge rather than stopping).
const double kSpiralOuterFrac = 0.66;

/// Radius of the hollow, glowing core, in arm pitches.
const double kSpiralCorePitches = 0.9;

/// Halftone screen cell in logical px (dot pitch).
const double kHalftoneCell = 11.0;

/// Motion rates for one field. Each is multiplied by [SpiralField.phase]: for
/// the generating field phase advances in drift radians (~2π per 15 s at rest,
/// faster while generating); for the welcome intro it advances in real seconds.
@immutable
class SpiralMotion {
  final double rotation; // rad per phase unit — whole-spiral spin
  final double flow; // arm pitches per phase unit — arms slide outward
  final double bead; // rad per phase unit — token beads run along the arms
  final double hue; // rad per phase unit — the two hues rotate along the arms
  final double starTime; // star twinkle seconds per phase unit
  final double starDrift; // px per phase unit — starfield parallax
  final double drift; // core float speed (Lissajous rate)
  const SpiralMotion({
    required this.rotation,
    required this.flow,
    required this.bead,
    required this.hue,
    required this.starTime,
    required this.starDrift,
    required this.drift,
  });
}

/// While generating: a visible spin, arms streaming outward and quick token
/// beads riding them.
const SpiralMotion kGeneratingMotion = SpiralMotion(
  rotation: 0.35,
  flow: 0.9,
  bead: 12.0,
  hue: 0.5,
  starTime: 2.4,
  starDrift: 6.0,
  drift: 0.7,
);

/// Welcome intro: the same spiral, barely turning, with no token beads — a
/// still starfield with a slow galaxy behind the greeting.
const SpiralMotion kWelcomeMotion = SpiralMotion(
  rotation: 0.12,
  flow: 0.12,
  bead: 0.0,
  hue: 0.25,
  starTime: 1.4,
  starDrift: 2.5,
  drift: 0.3,
);

/// Where the spiral sits this frame, in pixels / radians.
@immutable
class SpiralPlacement {
  final Offset center;
  final double pitch; // px between neighbouring arms
  final double rotation; // rad
  final double coreRadius; // px
  final double outerRadius; // px
  final double flow; // arm pitches the arms have travelled outward
  final double beadPhase; // rad
  final double hueDrift; // rad
  final double starTime; // s
  final double starDrift; // px
  const SpiralPlacement({
    required this.center,
    required this.pitch,
    required this.rotation,
    required this.coreRadius,
    required this.outerRadius,
    required this.flow,
    required this.beadPhase,
    required this.hueDrift,
    required this.starTime,
    required this.starDrift,
  });
}

/// Computes the spiral's placement for [phase] over a canvas of [size]. Pure.
SpiralPlacement spiralPlacement(double phase, Size size, {required bool welcome}) {
  final m = welcome ? kWelcomeMotion : kGeneratingMotion;
  final short = size.shortestSide;
  final diagonal = math.sqrt(size.width * size.width + size.height * size.height);
  final drift = kSpiralDriftAmt * short;
  final center = Offset(
    kSpiralAnchor.dx * size.width + drift * math.sin(phase * m.drift + 0.6),
    kSpiralAnchor.dy * size.height + drift * math.cos(phase * m.drift * 0.77 + 2.1),
  );
  final pitch = (kSpiralPitchFrac * short).clamp(kSpiralPitchMin, kSpiralPitchMax).toDouble();
  return SpiralPlacement(
    center: center,
    pitch: pitch,
    rotation: phase * m.rotation,
    coreRadius: pitch * kSpiralCorePitches,
    outerRadius: kSpiralOuterFrac * diagonal,
    flow: phase * m.flow,
    beadPhase: phase * m.bead,
    hueDrift: phase * m.hue,
    starTime: phase * m.starTime,
    starDrift: phase * m.starDrift,
  );
}

/// How strongly a field draws. The generating field is the show; the welcome
/// intro is a quieter, beadless version. Over a light idle colour the dots and
/// core are held back so body text on top stays comfortably legible.
@immutable
class SpiralLook {
  final double intensity; // dot coverage gain 0..1
  final double beadAmount; // 0 = even arms, 1 = full token beads
  final int arms;
  final double starStrength; // 0..1
  final double coreGlow; // 0..1
  const SpiralLook({
    required this.intensity,
    required this.beadAmount,
    required this.arms,
    required this.starStrength,
    required this.coreGlow,
  });
}

SpiralLook spiralLook({required bool welcome, required bool darkIdle}) {
  if (welcome) {
    return SpiralLook(
      intensity: darkIdle ? 0.55 : 0.40,
      beadAmount: 0.0,
      arms: 2,
      starStrength: darkIdle ? 1.0 : 0.6,
      coreGlow: 0.5,
    );
  }
  return SpiralLook(
    intensity: darkIdle ? 0.90 : 0.62,
    beadAmount: 1.0,
    arms: 3,
    starStrength: darkIdle ? 0.85 : 0.5,
    coreGlow: 0.8,
  );
}

/// Whether [idle] is a dark background (near-black wash) rather than a light one.
bool isDarkIdle(Color idle) => ThemeData.estimateBrightnessForColor(idle) == Brightness.dark;

/// The star / highlight colour: the mesh hues' average hue, pushed pale over a
/// dark idle and deep over a light one, so stars always read against the base.
/// Over a light idle the stars are also fewer and softer (see [spiralLook]):
/// dark specks on a pale wash read as grit long before pale ones on black do.
Color spiralHighlightColor(Color idle, Color a, Color b) {
  final mix = HSLColor.fromColor(Color.lerp(a, b, 0.5)!);
  return isDarkIdle(idle)
      ? HSLColor.fromAHSL(1.0, mix.hue, 0.35, 0.88).toColor()
      : HSLColor.fromAHSL(1.0, mix.hue, 0.60, 0.42).toColor();
}

/// Packs the field's per-frame state into the uniform buffer that
/// shaders/halftone_spiral.frag declares, one vec4 per [kSpiralUniformOrder]
/// entry:
///   uIdle(rgb,1) · uCanvas(rgb,o) · uColA(rgb,0) · uColB(rgb,0) ·
///   uStar(rgb, starStrength·o) · uSpiral(cx,cy,pitch,rotation) ·
///   uFlow(flow,beadPhase,beadAmount,arms) · uField(coreR,outerR,intensity,cell) ·
///   uTwinkle(starTime,starDrift,coreGlow,hueDrift).
/// Pure — unit-testable.
Float32List buildSpiralUniforms(SpiralField field, Color idle, Size size) {
  final o = field.opacity;
  final p = spiralPlacement(field.phase, size, welcome: field.welcome);
  final dark = isDarkIdle(idle);
  final look = spiralLook(welcome: field.welcome, darkIdle: dark);
  final star = spiralHighlightColor(idle, field.a, field.b);

  final u = Float32List(kSpiralUniformFloats);
  var k = 0;
  void w(double v) => u[k++] = v;
  void rgb(Color c, double w4) {
    w(c.r);
    w(c.g);
    w(c.b);
    w(w4);
  }

  rgb(idle, 1.0); // uIdle
  rgb(field.canvas, o); // uCanvas
  rgb(field.a, 0.0); // uColA
  rgb(field.b, 0.0); // uColB
  rgb(star, look.starStrength * o); // uStar
  w(p.center.dx); // uSpiral
  w(p.center.dy);
  w(p.pitch);
  w(p.rotation);
  w(p.flow); // uFlow
  w(p.beadPhase);
  w(look.beadAmount);
  w(look.arms.toDouble());
  w(p.coreRadius); // uField
  w(p.outerRadius);
  w(look.intensity);
  w(kHalftoneCell);
  w(p.starTime); // uTwinkle
  w(p.starDrift);
  w(look.coreGlow);
  w(p.hueDrift);
  assert(k == kSpiralUniformFloats);
  return u;
}
