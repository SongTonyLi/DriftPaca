import 'package:flutter/material.dart';
import 'streaming_cursor.dart';

/// Renders streaming text with per-word fade-in animation.
///
/// Each new chunk of words fades in with a staggered wave effect,
/// inspired by open-webui's token streaming animation. When streaming
/// completes, the parent should switch to MarkdownBody for full formatting.
class StreamingTextRenderer extends StatefulWidget {
  final String content;
  final TextStyle? baseStyle;
  final bool showCursor;

  const StreamingTextRenderer({
    super.key,
    required this.content,
    this.baseStyle,
    this.showCursor = true,
  });

  @override
  State<StreamingTextRenderer> createState() => _StreamingTextRendererState();
}

class _StreamingTextRendererState extends State<StreamingTextRenderer>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  String _stableContent = '';
  List<String> _newTokens = [];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1.0,
    );
    _newTokens = _tokenize(widget.content);
    if (_newTokens.isNotEmpty) {
      _fadeController.forward(from: 0.0);
    }
  }

  @override
  void didUpdateWidget(StreamingTextRenderer old) {
    super.didUpdateWidget(old);
    if (widget.content != old.content) {
      if (widget.content.startsWith(old.content)) {
        // Content was appended — animate only the delta
        _stableContent = old.content;
        _newTokens = _tokenize(widget.content.substring(old.content.length));
      } else {
        // Content changed entirely — re-animate all
        _stableContent = '';
        _newTokens = _tokenize(widget.content);
      }
      if (_newTokens.isNotEmpty) {
        _fadeController.forward(from: 0.0);
      }
    }
  }

  List<String> _tokenize(String text) {
    return RegExp(r'\S+|\s+').allMatches(text).map((m) => m[0]!).toList();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.baseStyle ??
        Theme.of(context).textTheme.bodyLarge ??
        const TextStyle(fontSize: 16);
    final baseColor = style.color ??
        DefaultTextStyle.of(context).style.color ??
        Theme.of(context).colorScheme.onSurface;

    return AnimatedBuilder(
      animation: _fadeController,
      builder: (context, _) {
        return Text.rich(
          TextSpan(
            style: style.copyWith(color: baseColor),
            children: [
              // Stable (old) content at full opacity
              if (_stableContent.isNotEmpty) TextSpan(text: _stableContent),
              // New tokens with staggered fade-in wave
              ..._buildAnimatedTokens(style, baseColor),
              // Blinking cursor at the end
              if (widget.showCursor)
                const WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: StreamingCursor(),
                ),
            ],
          ),
        );
      },
    );
  }

  List<InlineSpan> _buildAnimatedTokens(TextStyle style, Color baseColor) {
    if (_newTokens.isEmpty) return [];

    final wordCount =
        _newTokens.where((t) => t.trim().isNotEmpty).length.clamp(1, 999);
    int wordIndex = 0;

    return _newTokens.map((token) {
      if (token.trim().isEmpty) {
        return TextSpan(text: token) as InlineSpan;
      }

      // Staggered wave: each word starts fading slightly after the previous
      double opacity;
      if (wordCount <= 1) {
        opacity = Curves.easeOut.transform(_fadeController.value);
      } else {
        final staggerDelay = wordIndex / wordCount * 0.4;
        final wordProgress =
            ((_fadeController.value - staggerDelay) / (1.0 - staggerDelay))
                .clamp(0.0, 1.0);
        opacity = Curves.easeOut.transform(wordProgress);
      }

      wordIndex++;

      return TextSpan(
        text: token,
        style: style.copyWith(
          color: baseColor.withValues(alpha: opacity),
        ),
      ) as InlineSpan;
    }).toList();
  }
}
