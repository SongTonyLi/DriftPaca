import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:llamaseek/Utils/motion.dart';

/// Wraps streaming assistant markdown so each newly started line fades in.
///
/// Settled lines stay at full opacity and are never re-animated. The fade is a
/// [ShaderMask] over the last line of [child] — not a [WidgetSpan] inside the
/// text — so characters cannot overflow, stack, or flicker as tokens arrive.
/// History (`isStreaming: false`) and reduced motion skip the mask entirely.
class StreamingFadeText extends StatefulWidget {
  const StreamingFadeText({
    super.key,
    required this.text,
    required this.isStreaming,
    required this.child,
    this.duration = const Duration(milliseconds: 400),
  });

  final String text;
  final bool isStreaming;
  final Widget child;
  final Duration duration;

  @override
  StreamingFadeTextState createState() => StreamingFadeTextState();
}

class StreamingFadeTextState extends State<StreamingFadeText>
    with SingleTickerProviderStateMixin {
  /// Body line box from the markdown stylesheet: 16px at height 1.48.
  static const double _lineBand = 16.0 * 1.48;

  late final AnimationController _controller;
  late final Animation<double> _opacity;

  /// Opacity of the last-line fade. 1 means the line is settled.
  @visibleForTesting
  double get lineFadeOpacity => _opacity.value;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    // Text already on screen at mount is settled; only later lines fade.
    _controller.value = 1.0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (animationsDisabled(context)) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(StreamingFadeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isStreaming || animationsDisabled(context)) {
      _controller.value = 1.0;
      return;
    }
    if (oldWidget.text == widget.text) return;
    if (!widget.text.startsWith(oldWidget.text)) {
      // Rewrites (citation linking, truncated drafts) are not a new line.
      _controller.value = 1.0;
      return;
    }
    if (_startsNewLine(oldWidget.text, widget.text)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skipFade = !widget.isStreaming || animationsDisabled(context);
    if (skipFade) return widget.child;

    final scaler = MediaQuery.textScalerOf(context).clamp(
      minScaleFactor: 0.8,
      maxScaleFactor: 2.0,
    );
    final band = scaler.scale(_lineBand);

    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, child) {
        if (_controller.value >= 1.0) return child!;
        return ShaderMask(
          key: const ValueKey('streaming-last-line-fade'),
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => _lastLineShader(bounds, band, _opacity.value),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// True when [next] grew from [previous] onto a new line: a newline in the
/// appended tail, or the first characters after a trailing newline.
bool _startsNewLine(String previous, String next) {
  if (previous.isEmpty && next.isNotEmpty) return true;
  if (!next.startsWith(previous)) return false;
  final added = next.substring(previous.length);
  if (added.isEmpty) return false;
  return added.contains('\n') || previous.endsWith('\n');
}

Shader _lastLineShader(Rect bounds, double band, double opacity) {
  final visible = Color.fromRGBO(255, 255, 255, opacity);
  const opaque = Color.fromRGBO(255, 255, 255, 1);
  if (!bounds.isFinite || bounds.isEmpty) {
    return const LinearGradient(colors: [opaque, opaque]).createShader(bounds);
  }
  if (bounds.height <= band + 0.5) {
    return LinearGradient(colors: [visible, visible]).createShader(bounds);
  }
  final edge = (bounds.height - band) / bounds.height;
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [opaque, opaque, visible],
    stops: [0.0, edge, edge],
  ).createShader(bounds);
}
