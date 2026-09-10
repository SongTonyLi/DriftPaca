import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:llamaseek/Models/research_phase.dart';
import 'package:llamaseek/Utils/motion.dart';
import 'package:llamaseek/Widgets/pulsing_icon.dart';

/// How a phase's glyph moves. Only two mechanisms exist — a pulse and one
/// repeating controller — because a strip that used a different trick per
/// phase would read as decoration rather than as a status line.
enum _GlyphMotion {
  /// A model call is in flight: the same breathing sparkle the thinking
  /// block uses, so the two read as the same kind of waiting.
  pulse,

  /// Slow continuous rotation — the run is circling a goal it does not have
  /// words for yet.
  rotate,

  /// A small side-to-side sweep: the run is out looking at something.
  wiggle,

  /// Nothing is happening on our side. Used for the one phase blocked on a
  /// person, and for a finished run.
  still,
}

/// A pill that says what a research run is doing right now, and for how long.
///
/// Before this existed, most of a run looked identical from the outside: a
/// streaming llama and no other signal, whether the loop was framing a goal,
/// waiting on a search, or checking a draft against the objective. The strip
/// names the current [ResearchPhase] and counts the seconds spent in it, so a
/// long phase reads as progress rather than as a hang.
///
/// It lives only on the streaming bubble: it holds a repeating controller and
/// a 250 ms timer, both released in [dispose]. Under reduced motion the glyph
/// is static and the label cuts instead of dissolving.
class ResearchActivityStrip extends StatefulWidget {
  final ResearchPhase phase;

  /// When the current phase began. Null means no counter — the caller does
  /// not know, so the strip does not guess.
  final DateTime? startedAt;

  const ResearchActivityStrip({
    super.key,
    required this.phase,
    this.startedAt,
  });

  @override
  State<ResearchActivityStrip> createState() => _ResearchActivityStripState();
}

class _ResearchActivityStripState extends State<ResearchActivityStrip>
    with SingleTickerProviderStateMixin {
  static const Duration _tick = Duration(milliseconds: 250);
  static const Duration _rotatePeriod = Duration(milliseconds: 2600);
  static const Duration _wigglePeriod = Duration(milliseconds: 900);

  late final AnimationController _glyph;
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _animationsDisabled = false;

  @override
  void initState() {
    super.initState();
    _glyph = AnimationController(vsync: this, duration: _rotatePeriod);
    _restartCounter();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animationsDisabled = animationsDisabled(context);
    _syncGlyphMotion();
  }

  @override
  void didUpdateWidget(ResearchActivityStrip old) {
    super.didUpdateWidget(old);
    if (widget.phase != old.phase || widget.startedAt != old.startedAt) {
      _restartCounter();
    }
    if (widget.phase != old.phase) _syncGlyphMotion();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _glyph.dispose();
    super.dispose();
  }

  /// Restarts the in-phase counter. The elapsed total is seeded from
  /// [ResearchActivityStrip.startedAt] and then advanced by the timer itself
  /// rather than re-read from the wall clock: the timer is the thing that is
  /// actually scheduled, so the two can never disagree about which second is
  /// on screen.
  void _restartCounter() {
    _timer?.cancel();
    _timer = null;
    final startedAt = widget.startedAt;
    if (startedAt == null) {
      _elapsed = Duration.zero;
      return;
    }
    final since = DateTime.now().difference(startedAt);
    _elapsed = since.isNegative ? Duration.zero : since;
    _timer = Timer.periodic(_tick, (_) {
      if (!mounted) return;
      final next = _elapsed + _tick;
      final rolled = next.inSeconds != _elapsed.inSeconds;
      _elapsed = next;
      // Four ticks a second, at most one rebuild: the counter only ever
      // shows whole seconds.
      if (rolled) setState(() {});
    });
  }

  void _syncGlyphMotion() {
    final motion = _motionFor(widget.phase);
    if (_animationsDisabled ||
        (motion != _GlyphMotion.rotate && motion != _GlyphMotion.wiggle)) {
      _glyph
        ..stop()
        ..value = 0.0;
      return;
    }
    final period =
        motion == _GlyphMotion.rotate ? _rotatePeriod : _wigglePeriod;
    if (_glyph.duration != period) {
      _glyph
        ..stop()
        ..duration = period
        ..value = 0.0;
    }
    if (!_glyph.isAnimating) _glyph.repeat();
  }

  static _GlyphMotion _motionFor(ResearchPhase phase) => switch (phase) {
        ResearchPhase.framingGoal => _GlyphMotion.rotate,
        ResearchPhase.awaitingClarification => _GlyphMotion.still,
        ResearchPhase.thinking => _GlyphMotion.pulse,
        ResearchPhase.searching => _GlyphMotion.wiggle,
        ResearchPhase.reading => _GlyphMotion.pulse,
        ResearchPhase.checkingCoverage => _GlyphMotion.pulse,
        ResearchPhase.drafting => _GlyphMotion.wiggle,
        ResearchPhase.done => _GlyphMotion.still,
      };

  static IconData _iconFor(ResearchPhase phase) => switch (phase) {
        ResearchPhase.framingGoal => Icons.center_focus_weak,
        ResearchPhase.awaitingClarification => Icons.help_outline,
        // The thinking block's sparkle, so the two read as one thing.
        ResearchPhase.thinking => Icons.auto_awesome,
        ResearchPhase.searching => Icons.search,
        ResearchPhase.reading => Icons.menu_book_outlined,
        ResearchPhase.checkingCoverage => Icons.fact_check_outlined,
        ResearchPhase.drafting => Icons.edit_outlined,
        ResearchPhase.done => Icons.check_circle_outline,
      };

  Widget _buildGlyph(Color color) {
    final icon = _iconFor(widget.phase);
    switch (_motionFor(widget.phase)) {
      case _GlyphMotion.pulse:
        // PulsingIcon settles itself under reduced motion.
        return PulsingIcon(icon: icon, size: 14, color: color);
      case _GlyphMotion.rotate:
        return RotationTransition(
          turns: _glyph,
          child: Icon(icon, size: 14, color: color),
        );
      case _GlyphMotion.wiggle:
        return AnimatedBuilder(
          animation: _glyph,
          // A sine sweep rather than a reversing tween so the resting value
          // (0, which is where reduced motion parks it) is dead centre.
          builder: (context, child) => Transform.translate(
            offset: Offset(math.sin(_glyph.value * 2 * math.pi) * 1.5, 0),
            child: child,
          ),
          child: Icon(icon, size: 14, color: color),
        );
      case _GlyphMotion.still:
        return Icon(icon, size: 14, color: color);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ) ??
        TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12);
    final seconds = _elapsed.inSeconds;

    return Semantics(
      container: true,
      liveRegion: true,
      // The phase alone: a live region that re-read the second counter would
      // interrupt a screen-reader user every second of a run.
      label: widget.phase.label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildGlyph(color),
            const SizedBox(width: 6),
            AnimatedSwitcher(
              duration:
                  motionDuration(context, const Duration(milliseconds: 240)),
              child: Text(
                widget.phase.label,
                key: ValueKey(widget.phase),
                style: labelStyle,
              ),
            ),
            // Only from a full second: a number that blinks 0s onto every
            // fast phase is noise, not information.
            if (seconds > 0) ...[
              const SizedBox(width: 6),
              Text(
                '${seconds}s',
                style: labelStyle.copyWith(
                  color: color.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
