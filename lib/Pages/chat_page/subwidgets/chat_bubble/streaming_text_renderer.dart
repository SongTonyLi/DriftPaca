import 'package:flutter/material.dart';
import 'streaming_llama.dart';

/// Renders streaming text with per-word fade-in animation.
///
/// Unlike a shared AnimationController that resets on every content update,
/// each word tracks its own creation timestamp. Opacity is calculated as
/// `elapsed / fadeDuration`, so each word independently fades in over
/// [_fadeDurationSec] seconds regardless of how fast or slow new tokens arrive.
///
/// Words in the same batch get a small stagger delay so bursts of tokens
/// produce a flowing wave rather than a simultaneous flash.
///
/// For performance, words that have finished animating are graduated into
/// a single [_stableContent] string rendered as one efficient [TextSpan].
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
  late AnimationController _tickController;
  final Stopwatch _stopwatch = Stopwatch();

  /// Content that has finished animating — rendered as one TextSpan.
  String _stableContent = '';

  /// Words currently undergoing fade-in animation.
  final List<_WordEntry> _animatingWords = [];

  /// Each word fades from invisible to fully opaque over this duration.
  static const double _fadeDurationSec = 0.14; // 140ms

  /// Stagger between consecutive words in the same batch.
  static const double _staggerPerWord = 0.012; // 12ms per word

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
    _tickController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _appendTokens(widget.content);
  }

  @override
  void didUpdateWidget(StreamingTextRenderer old) {
    super.didUpdateWidget(old);
    if (widget.content != old.content) {
      _graduateCompletedWords();
      if (widget.content.startsWith(old.content)) {
        _appendTokens(widget.content.substring(old.content.length));
      } else {
        _stableContent = '';
        _animatingWords.clear();
        _appendTokens(widget.content);
      }
    }
  }

  /// Splits [newText] into word/whitespace tokens and adds them with stagger.
  void _appendTokens(String newText) {
    if (newText.isEmpty) return;

    final now = _stopwatch.elapsedMilliseconds / 1000.0;
    final matches = RegExp(r'\S+|\s+').allMatches(newText);

    int wordIdx = 0;
    for (final m in matches) {
      final text = m[0]!;
      final isWord = text.trim().isNotEmpty;
      _animatingWords.add(_WordEntry(
        text: text,
        createdAt: now,
        stagger: isWord ? (wordIdx * _staggerPerWord).clamp(0.0, 0.15) : 0.0,
      ));
      if (isWord) wordIdx++;
    }

    if (!_tickController.isAnimating) _tickController.repeat();
  }

  /// Promotes fully-faded-in words to [_stableContent] so only recent words
  /// remain in the per-frame loop.
  void _graduateCompletedWords() {
    final now = _stopwatch.elapsedMilliseconds / 1000.0;
    while (_animatingWords.isNotEmpty) {
      final w = _animatingWords.first;
      if ((now - w.createdAt - w.stagger) >= _fadeDurationSec + 0.05) {
        _stableContent += _animatingWords.removeAt(0).text;
      } else {
        break;
      }
    }
  }

  @override
  void dispose() {
    _tickController.dispose();
    _stopwatch.stop();
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
      animation: _tickController,
      builder: (context, _) {
        final now = _stopwatch.elapsedMilliseconds / 1000.0;

        // Stop ticking when every word is fully visible
        final allDone = _animatingWords.every(
          (w) => w.text.trim().isEmpty || (now - w.createdAt - w.stagger) >= _fadeDurationSec,
        );
        if (allDone && _tickController.isAnimating) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _graduateCompletedWords();
              if (_animatingWords.isEmpty) _tickController.stop();
            }
          });
        }

        return Text.rich(
          TextSpan(
            style: style.copyWith(color: baseColor),
            children: [
              if (_stableContent.isNotEmpty) TextSpan(text: _stableContent),
              for (final w in _animatingWords) _span(w, style, baseColor, now),
              if (widget.showCursor)
                const WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: StreamingLlama(),
                ),
            ],
          ),
        );
      },
    );
  }

  InlineSpan _span(_WordEntry w, TextStyle style, Color baseColor, double now) {
    if (w.text.trim().isEmpty) return TextSpan(text: w.text);

    final elapsed = now - w.createdAt - w.stagger;
    final t = (elapsed / _fadeDurationSec).clamp(0.0, 1.0);
    if (t >= 1.0) return TextSpan(text: w.text);

    return TextSpan(
      text: w.text,
      style: TextStyle(color: baseColor.withValues(alpha: Curves.easeOut.transform(t))),
    );
  }
}

class _WordEntry {
  final String text;
  final double createdAt;
  final double stagger;
  _WordEntry({required this.text, required this.createdAt, this.stagger = 0.0});
}
