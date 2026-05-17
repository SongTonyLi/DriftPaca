import 'package:flutter/material.dart';

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
    final closeIndex = content.indexOf(closeTag);

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

  const ThinkBlockWidget({
    super.key,
    required this.content,
    required this.isComplete,
    this.isStreaming = false,
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

  late final AnimationController _pulseController;
  late final AnimationController _expandController;
  late final Animation<double> _expandCurve;

  bool get _isExpanded {
    if (_userToggle != null) return _userToggle!;
    return !widget.isComplete;
  }

  @override
  void initState() {
    super.initState();
    _wasAlreadyComplete = widget.isComplete;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Start expanded if streaming, collapsed if loaded from history
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      value: _wasAlreadyComplete ? 0.0 : 1.0,
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

  void _startTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || !_stopwatch.isRunning) return false;
      setState(() {
        _elapsedSeconds = _stopwatch.elapsed.inSeconds;
      });
      return true;
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
      if (_userToggle == null) {
        _userToggle = false;
        // Smooth auto-collapse after a brief pause
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _expandController.reverse();
        });
      }
    }
  }

  @override
  void dispose() {
    _stopwatch.stop();
    _pulseController.dispose();
    _expandController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _userToggle = !_isExpanded);
    if (_isExpanded) {
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
    if (_wasAlreadyComplete) {
      return 'Thought';
    }
    return _elapsedSeconds > 0
        ? 'Thought for $_elapsedSeconds seconds'
        : 'Thought';
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
                    opacity: Tween(begin: 0.3, end: 1.0)
                        .animate(_pulseController),
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
                child: SelectableText(
                  widget.content,
                  style:
                      TextStyle(color: color, fontSize: 13, height: 1.4),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
