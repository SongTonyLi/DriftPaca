import 'dart:async';
import 'package:flutter/material.dart';
import 'package:llamaseek/Utils/motion.dart';
import 'package:llamaseek/Widgets/token_reveal_text.dart';

/// Parses message content into thinking and response parts.
class ThinkBlockParser {
  final String thinkContent;
  final String responseContent;
  final bool isThinkingComplete;

  ThinkBlockParser._({
    required this.thinkContent,
    required this.responseContent,
    required this.isThinkingComplete,
  });

  static ThinkBlockParser? tryParse(String content) {
    if (!content.trimLeft().startsWith('<think>')) return null;

    final openTag = '<think>';
    final closeTag = '</think>';
    final openIndex = content.indexOf(openTag);
    final closeIndex = content.lastIndexOf(closeTag);

    if (closeIndex == -1) {
      final thinkContent = content.substring(openIndex + openTag.length).trim();
      return ThinkBlockParser._(
        thinkContent: thinkContent,
        responseContent: '',
        isThinkingComplete: false,
      );
    } else {
      final thinkContent =
          content.substring(openIndex + openTag.length, closeIndex).trim();
      final responseContent =
          content.substring(closeIndex + closeTag.length).trim();
      return ThinkBlockParser._(
        thinkContent: thinkContent,
        responseContent: responseContent,
        isThinkingComplete: true,
      );
    }
  }
}

/// Collapsible thinking block with pulsing sparkle, duration timer,
/// and smooth animated expand/collapse.
class ThinkBlockWidget extends StatefulWidget {
  final String content;
  final bool isComplete;
  final bool isStreaming;
  final bool keepExpandedWhenComplete;

  /// How long this stretch of reasoning actually took, when something else
  /// measured it — the research loop's live thinking segment, or a
  /// persisted message that recorded it. Preferred over this widget's own
  /// stopwatch, which can only ever measure how long the BLOCK has been on
  /// screen: a block built from history was never here while the model was
  /// thinking, and a live block hands over its authoritative total the
  /// moment its turn ends.
  final int? elapsedSeconds;

  const ThinkBlockWidget({
    super.key,
    required this.content,
    required this.isComplete,
    this.isStreaming = false,
    this.keepExpandedWhenComplete = false,
    this.elapsedSeconds,
  });

  @override
  State<ThinkBlockWidget> createState() => _ThinkBlockWidgetState();
}

class _ThinkBlockWidgetState extends State<ThinkBlockWidget>
    with TickerProviderStateMixin {
  bool? _userToggle;
  final Stopwatch _stopwatch = Stopwatch();
  late final bool _wasAlreadyComplete;
  int _elapsedSeconds = 0;
  Timer? _timer;
  Timer? _autoCollapseTimer;
  bool _animationsDisabled = false;

  late final AnimationController _pulseController;
  late final AnimationController _expandController;
  late final Animation<double> _expandCurve;
  late final Animation<double> _pulseOpacity;

  bool get _isExpanded {
    if (_userToggle != null) return _userToggle!;
    return widget.keepExpandedWhenComplete || !widget.isComplete;
  }

  @override
  void initState() {
    super.initState();
    _wasAlreadyComplete = widget.isComplete;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseOpacity = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Start expanded if streaming, collapsed if loaded from history
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      value: (_wasAlreadyComplete && !widget.keepExpandedWhenComplete) ? 0.0 : 1.0,
    );
    _expandCurve = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    if (!widget.isComplete) {
      _stopwatch.start();
      _startTimer();
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animationsDisabled = animationsDisabled(context);
    if (_animationsDisabled) {
      _pulseController.stop();
      _pulseController.value = 1.0;
      _expandController.value = _isExpanded ? 1.0 : 0.0;
    } else if (!widget.isComplete && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_stopwatch.isRunning) {
        _timer?.cancel();
        return;
      }
      setState(() {
        _elapsedSeconds = _stopwatch.elapsed.inSeconds;
      });
    });
  }

  @override
  void didUpdateWidget(ThinkBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shouldStop = (!oldWidget.isComplete && widget.isComplete) ||
        (oldWidget.isStreaming && !widget.isStreaming && !widget.isComplete);
    if (shouldStop && _stopwatch.isRunning) {
      _stopwatch.stop();
      _elapsedSeconds = _stopwatch.elapsed.inSeconds;
      _pulseController.stop();
      if (_userToggle == null && !widget.keepExpandedWhenComplete) {
        _autoCollapseTimer?.cancel();
        _autoCollapseTimer = Timer(
          motionDuration(context, const Duration(milliseconds: 300)),
          () {
            if (!mounted || _userToggle != null) return;
            setState(() => _userToggle = false);
            if (_animationsDisabled) {
              _expandController.value = 0.0;
            } else {
              _expandController.reverse();
            }
          },
        );
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _autoCollapseTimer?.cancel();
    _stopwatch.stop();
    _pulseController.dispose();
    _expandController.dispose();
    super.dispose();
  }

  void _toggle() {
    _autoCollapseTimer?.cancel();
    setState(() => _userToggle = !_isExpanded);
    if (_animationsDisabled) {
      _expandController.value = _isExpanded ? 1.0 : 0.0;
    } else if (_isExpanded) {
      _expandController.forward();
    } else {
      _expandController.reverse();
    }
  }

  String get _label {
    final stopped = !_stopwatch.isRunning;
    if (!widget.isComplete && !stopped) {
      return _elapsedSeconds > 0
          ? 'Thinking... ${_elapsedSeconds}s'
          : 'Thinking...';
    }
    // A block that was built already complete has no stopwatch reading of
    // its own worth showing (it would time how long it has been scrolled
    // into view), so it names a duration only when it was handed one.
    final seconds =
        widget.elapsedSeconds ?? (_wasAlreadyComplete ? 0 : _elapsedSeconds);
    return seconds > 0 ? 'Thought for $seconds seconds' : 'Thought';
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.secondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!widget.isComplete)
                  FadeTransition(
                    opacity: _pulseOpacity,
                    child:
                        Icon(Icons.auto_awesome, color: color, size: 16),
                  )
                else
                  Icon(Icons.auto_awesome, color: color, size: 16),
                const SizedBox(width: 4),
                Text(
                  _label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 2),
                AnimatedBuilder(
                  animation: _expandCurve,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: _expandCurve.value * 1.5708, // 0 → 90°
                      child: child,
                    );
                  },
                  child: Icon(
                    Icons.keyboard_arrow_right,
                    color: color,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
        ClipRect(
          child: SizeTransition(
            sizeFactor: _expandCurve,
            axisAlignment: -1.0,
            child: FadeTransition(
              opacity: _expandCurve,
              child: Padding(
                padding: const EdgeInsets.only(
                    left: 24.0, top: 4.0, bottom: 8.0),
                // Plain Text — selection is provided by the SelectionArea in
                // chat_list_view. SelectableText here would intercept vertical
                // drags inside the chat list and block page scroll.
                //
                // Revealed a character at a time while the block is open, so
                // reasoning arriving in bursty chunks reads as thinking rather
                // than as a series of jumps. A block that is already complete
                // (all of history) renders in full on its first frame.
                child: TokenRevealText(
                  widget.content,
                  style:
                      TextStyle(color: color, fontSize: 13, height: 1.4),
                  // Paused while folded away: a SizeTransition does not
                  // mute TickerMode, so without this a collapsed live block
                  // would keep revealing into a zero-height box.
                  revealing: !widget.isComplete && _isExpanded,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
