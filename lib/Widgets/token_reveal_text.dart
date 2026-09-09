import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:llamaseek/Utils/motion.dart';
import 'package:llamaseek/Utils/surrogate_safe_length.dart';

/// A plain [Text] that types out whatever is appended to it while it is live.
///
/// The assistant bubble already reveals its markdown this way; this is the
/// same idea for prose that is not markdown — the research loop's reasoning,
/// which arrives in bursty 32 ms chunks and, rendered directly, reads as a
/// series of jumps rather than as thinking happening.
///
/// Two rules keep it honest:
///
/// * It starts fully revealed. Text present at creation is history (a saved
///   message, or a block scrolled back into view) and typing it out again
///   would claim it is being produced now. Only text appended after creation
///   is revealed.
/// * It never spends a frame showing half of a code point: the cut goes
///   through [surrogateSafeLength], so an emoji appears whole or not at all.
///
/// `revealing: false` (a finished block) and reduced motion both render the
/// full text and hold no ticker.
class TokenRevealText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  /// Whether more text is still expected. A block that is already complete
  /// shows everything at once — there is nothing left to reveal.
  final bool revealing;

  const TokenRevealText(
    this.text, {
    super.key,
    this.style,
    this.revealing = true,
  });

  @override
  State<TokenRevealText> createState() => _TokenRevealTextState();
}

class _TokenRevealTextState extends State<TokenRevealText>
    with SingleTickerProviderStateMixin {
  /// Gentle pace when there is barely anything to catch up on, so a slow
  /// trickle of tokens still reads as typing rather than as a stutter.
  static const double _baseCharsPerFrame = 0.7;

  /// Drain any backlog within ~this many frames (~0.75 s at 60 fps). A bursty
  /// chunk should be visibly typed, not spelled out for seconds after the
  /// model has moved on.
  static const int _revealFrameBudget = 45;

  int _revealed = 0;
  double _progress = 0;
  Ticker? _ticker;
  bool _animationsDisabled = false;

  bool get _shouldReveal => widget.revealing && !_animationsDisabled;

  @override
  void initState() {
    super.initState();
    _settle();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animationsDisabled = animationsDisabled(context);
    if (!_shouldReveal) {
      _settle();
    } else {
      _ensureTicker();
    }
  }

  @override
  void didUpdateWidget(TokenRevealText old) {
    super.didUpdateWidget(old);
    if (!_shouldReveal) {
      _settle();
      return;
    }
    // Content can shrink as well as grow (a rejected draft is cleared by
    // handing the same widget a shorter string); a cursor left past the end
    // would make the next substring throw.
    if (_revealed > widget.text.length) {
      _revealed = widget.text.length;
      _progress = _revealed.toDouble();
    }
    _ensureTicker();
  }

  void _settle() {
    _revealed = widget.text.length;
    _progress = _revealed.toDouble();
    _ticker?.stop();
  }

  void _ensureTicker() {
    if (_revealed >= widget.text.length) return;
    // One Ticker for the widget's lifetime, created on first need: a block
    // that never streams (all of history) never allocates one. Through the
    // provider, so it is muted with the rest of the route when this block is
    // no longer on screen.
    _ticker ??= createTicker(_onTick);
    if (!_ticker!.isActive) _ticker!.start();
  }

  void _onTick(Duration elapsed) {
    if (!_shouldReveal || _revealed >= widget.text.length) {
      _ticker?.stop();
      return;
    }
    final remaining = widget.text.length - _revealed;
    final budgetPace = remaining / _revealFrameBudget;
    _progress +=
        budgetPace > _baseCharsPerFrame ? budgetPace : _baseCharsPerFrame;
    final next = _progress.floor().clamp(0, widget.text.length);
    // Only a whole new character is worth a rebuild; sub-character progress
    // would repaint the same string 60 times a second.
    if (next != _revealed) {
      setState(() => _revealed = next);
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shouldReveal
        ? widget.text.substring(
            0, surrogateSafeLength(widget.text, _revealed))
        : widget.text;
    return Text(shown, style: widget.style);
  }
}
