import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand_node.dart';

/// One node's render data, decoupled from OllamaModel so the wheel stays a pure
/// UI control.
@immutable
class WheelNode {
  final String asset;
  final Color accent;
  final bool tinted; // draw the logo tinted to the foreground (mono/fallback)
  const WheelNode({
    required this.asset,
    required this.accent,
    this.tinted = false,
  });
}

/// A rotary "orrery" of provider logos. The user drags the ring (or flings, or
/// scrolls); it spins with momentum and snaps the nearest node under the top
/// notch (▼). Each detent crossing fires a haptic tick + a notch pulse and
/// reports the new index through [onSelectedChanged].
///
/// The ring leaves a hole in the middle for the page's center disc; this widget
/// paints only the orbiting nodes and the notch.
class LogoWheel extends StatefulWidget {
  final List<WheelNode> nodes;
  final int initialIndex;
  final ValueChanged<int> onSelectedChanged;

  /// Overall square size of the wheel.
  final double diameter;

  /// Diameter of the reserved center hole (the page's disc sits here); nodes
  /// orbit between this and the outer edge.
  final double centerHole;

  const LogoWheel({
    super.key,
    required this.nodes,
    required this.onSelectedChanged,
    this.initialIndex = 0,
    this.diameter = 340,
    this.centerHole = 184,
  });

  @override
  State<LogoWheel> createState() => _LogoWheelState();
}

class _LogoWheelState extends State<LogoWheel>
    with TickerProviderStateMixin {
  // Rotation of the ring in radians. Item i sits at screen angle
  // (-pi/2 + i*step - rotation); item i is docked when rotation == i*step.
  final ValueNotifier<double> _rotation = ValueNotifier<double>(0);
  // Bumped on every detent crossing to pulse the notch.
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);

  late final AnimationController _spin; // 0..1 driver for momentum + snap
  late final AnimationController _entrance; // one-shot bloom-in on mount
  double _animBegin = 0;
  double _animEnd = 0;

  int _lastDetent = 0;

  // Drag state.
  double? _lastAngle;
  double _velocity = 0; // d(rotation)/dt, smoothed (rad/s)
  Duration? _lastStamp;

  int get _n => widget.nodes.length;
  double get _step => (2 * math.pi) / math.max(1, _n);

  @override
  void initState() {
    super.initState();
    // Bounded 0..1 progress driver for momentum/snap. (Unbounded + forward()
    // would animate toward +infinity, blowing up Curves.transform.)
    _spin = AnimationController(vsync: this)
      ..addListener(_onSpinTick)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) HapticFeedback.lightImpact();
      });
    _rotation.value = widget.initialIndex * _step;
    _lastDetent = widget.initialIndex;
    _entrance = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 720))
      ..forward();
  }

  @override
  void dispose() {
    _spin.dispose();
    _entrance.dispose();
    _rotation.dispose();
    _tick.dispose();
    super.dispose();
  }

  int _wrap(int i) => ((i % _n) + _n) % _n;

  /// Apply a rotation, firing a haptic tick + notch pulse + selection callback
  /// whenever the detent under the notch changes.
  void _setRotation(double r) {
    _rotation.value = r;
    final d = (r / _step).round();
    if (d != _lastDetent) {
      _lastDetent = d;
      HapticFeedback.selectionClick();
      _tick.value++;
      widget.onSelectedChanged(_wrap(d));
    }
  }

  void _onSpinTick() {
    final t = Curves.decelerate.transform(_spin.value);
    _setRotation(lerpDouble(_animBegin, _animEnd, t)!);
  }

  void _animateRotation(double target, double speed) {
    _spin.stop();
    final begin = _rotation.value;
    final dist = (target - begin).abs();
    if (dist < 1e-4) {
      _setRotation(target);
      return;
    }
    _animBegin = begin;
    _animEnd = target;
    final secs = (dist / speed.clamp(2.0, 32.0)).clamp(0.28, 1.1);
    _spin
      ..duration = Duration(milliseconds: (secs * 1000).round())
      ..forward(from: 0);
  }

  // --- geometry -------------------------------------------------------------

  double _angleOf(Offset local) {
    final c = Offset(widget.diameter / 2, widget.diameter / 2);
    final v = local - c;
    return math.atan2(v.dy, v.dx);
  }

  static double _norm(double a) {
    while (a > math.pi) {
      a -= 2 * math.pi;
    }
    while (a < -math.pi) {
      a += 2 * math.pi;
    }
    return a;
  }

  // --- gestures -------------------------------------------------------------

  void _onPanStart(DragStartDetails d) {
    _spin.stop();
    _lastAngle = _angleOf(d.localPosition);
    _velocity = 0;
    _lastStamp = d.sourceTimeStamp;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final a = _angleOf(d.localPosition);
    final delta = _norm(a - (_lastAngle ?? a));
    _lastAngle = a;
    _setRotation(_rotation.value - delta);

    final ts = d.sourceTimeStamp;
    if (ts != null && _lastStamp != null) {
      final dt = (ts - _lastStamp!).inMicroseconds / 1e6;
      if (dt > 0) {
        final inst = -delta / dt;
        _velocity = _velocity * 0.55 + inst * 0.45;
      }
    }
    _lastStamp = ts;
  }

  void _onPanEnd(DragEndDetails d) {
    // Project where friction would carry the ring, then snap to that detent.
    const friction = 4.5;
    final projected = _rotation.value + _velocity / friction;
    final target = (projected / _step).round() * _step;
    _animateRotation(target, _velocity.abs());
  }

  /// Animate the nearest copy of [index] to the notch (used by node taps).
  void _selectIndex(int index) {
    final curDetent = (_rotation.value / _step).round();
    final revs = ((curDetent - index) / _n).round();
    _animateRotation((index + revs * _n) * _step, 9.0);
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      final dir = e.scrollDelta.dy > 0 ? 1 : -1;
      final cur = (_rotation.value / _step).round();
      _animateRotation((cur + dir) * _step, 9.0);
    }
  }

  // --- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: SizedBox(
          width: widget.diameter,
          height: widget.diameter,
          child: AnimatedBuilder(
            animation: _entrance,
            builder: (context, child) {
              final e = Curves.easeOutCubic.transform(_entrance.value);
              return Opacity(
                opacity: e,
                child: Transform.scale(scale: 0.9 + 0.1 * e, child: child),
              );
            },
            child: AnimatedBuilder(
              animation: _rotation,
              builder: (context, _) => _buildRing(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRing() {
    final half = widget.diameter / 2;
    final holeR = widget.centerHole / 2;
    final ringR = holeR + (half - holeR) * 0.56;
    const topAngle = -math.pi / 2;

    // Even spacing along the ring; size logos so neighbours never overlap, and
    // only render logos within a small arc of the notch — the rest are quiet
    // brand-coloured dots, so a long model list reads as a calm ring of dots
    // instead of a pile-up of logos.
    final spacing = (2 * math.pi * ringR) / math.max(1, _n);
    final rawLogo = math.min(widget.diameter * 0.15, spacing * 0.9);
    final logoSize = rawLogo < 20.0 ? 20.0 : rawLogo;
    final dotSize = (widget.diameter * 0.022).clamp(4.5, 9.0).toDouble();
    final topArc = _step * 2.5;

    final rotation = _rotation.value;
    final children = <Widget>[];

    for (var i = 0; i < _n; i++) {
      final node = widget.nodes[i];
      final ang = topAngle + i * _step - rotation;
      final dist = _norm(ang - topAngle).abs(); // 0 at notch → pi at bottom
      final depth = 1.0 - (dist / math.pi).clamp(0.0, 1.0);
      final cx = half + math.cos(ang) * ringR;
      final cy = half + math.sin(ang) * ringR;

      if (dist < topArc) {
        // Near the notch: bloom from a dot into a full logo.
        final w = (dist / topArc).clamp(0.0, 1.0).toDouble(); // 0 notch → 1 edge
        final logoOpacity =
            (1.0 - Curves.easeIn.transform(w)).clamp(0.0, 1.0).toDouble();
        final scale = lerpDouble(1.0, 0.62, Curves.easeOut.transform(w))!;
        // A dot fades in toward the arc edge so the logo→dot handoff is seamless.
        if (w > 0.4) {
          children.add(_dot(cx, cy, dotSize, node, depth * w));
        }
        children.add(Positioned(
          left: cx - logoSize / 2,
          top: cy - logoSize / 2,
          width: logoSize,
          height: logoSize,
          child: Opacity(
            opacity: logoOpacity,
            child: Transform.scale(
              scale: scale,
              child: GestureDetector(
                onTap: () => _selectIndex(i),
                child: BrandNode(
                  asset: node.asset,
                  accent: node.accent,
                  tinted: node.tinted,
                  size: logoSize,
                  prominence: depth,
                ),
              ),
            ),
          ),
        ));
      } else {
        // Everything else is a quiet dot.
        children.add(_dot(cx, cy, dotSize, node, 0.25 + 0.45 * depth));
      }
    }

    // Notch marker pinned at the top, pulsing on each detent crossing.
    children.add(Positioned(
      left: half - 16,
      top: half - (half - 8) - 2,
      width: 32,
      height: 26,
      child: _NotchPulse(tick: _tick),
    ));

    return Stack(clipBehavior: Clip.none, children: children);
  }

  Widget _dot(
      double cx, double cy, double size, WheelNode node, double opacity) {
    final color = node.accent;
    return Positioned(
      left: cx - size / 2,
      top: cy - size / 2,
      width: size,
      height: size,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0).toDouble(),
        child: DecoratedBox(
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ),
    );
  }
}

/// The ▼ indicator at 12 o'clock. Listens to [tick] and plays a brief
/// scale + glow pulse on every detent crossing — the visual counterpart to the
/// haptic that a browser preview can't deliver.
class _NotchPulse extends StatefulWidget {
  final ValueNotifier<int> tick;
  const _NotchPulse({required this.tick});

  @override
  State<_NotchPulse> createState() => _NotchPulseState();
}

class _NotchPulseState extends State<_NotchPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1.0,
    );
    widget.tick.addListener(_pulse);
  }

  void _pulse() => _c.forward(from: 0);

  @override
  void dispose() {
    widget.tick.removeListener(_pulse);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final pulse = 1.0 - Curves.easeOut.transform(_c.value); // 1 → 0
        final scale = 1.0 + 0.5 * pulse;
        return Transform.scale(
          scale: scale,
          child: Icon(
            Icons.arrow_drop_down_rounded,
            size: 30,
            color: Color.lerp(
              cs.onSurface.withValues(alpha: 0.55),
              cs.primary,
              pulse,
            ),
            shadows: pulse < 0.05
                ? null
                : [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.6 * pulse),
                      blurRadius: 14 * pulse,
                    ),
                  ],
          ),
        );
      },
    );
  }
}
