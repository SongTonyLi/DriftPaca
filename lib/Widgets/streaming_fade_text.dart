import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:llamaseek/Utils/motion.dart';
import 'package:llamaseek/Utils/surrogate_safe_length.dart';

/// Forces following [WidgetSpan]s onto the next line. A `\n` [TextSpan]
/// before a [WidgetSpan] floats the placeholder onto the previous line
/// (see the `<br>` builder on the assistant bubble).
const WidgetSpan _forcedLineBreak = WidgetSpan(
  child: SizedBox(width: double.infinity, height: 0),
);

/// Streaming assistant text as an ordered list of chunks. New tokens start at
/// opacity 0 and ease to 1; settled text is a plain [TextSpan] and is never
/// re-animated. History (`isStreaming: false`) and reduced motion skip the
/// controllers entirely.
class StreamingFadeText extends StatefulWidget {
  const StreamingFadeText({
    super.key,
    required this.text,
    required this.isStreaming,
    this.style,
    this.duration = const Duration(milliseconds: 400),
  });

  final String text;
  final bool isStreaming;
  final TextStyle? style;
  final Duration duration;

  @override
  State<StreamingFadeText> createState() => _StreamingFadeTextState();
}

class _StreamingFadeTextState extends State<StreamingFadeText> {
  /// WidgetSpan placeholders wrap like an unbreakable run. Keep the fading
  /// tail at or under one typical word so settle cannot reflow the paragraph.
  static const int _maxAnimatingChars = 32;

  final List<_Chunk> _chunks = <_Chunk>[];
  String _assembled = '';

  /// Deltas received since the last build. Flushed at the start of [build]
  /// so same-frame appends become one chunk *before* any [_FadeChunk] starts.
  String _queued = '';
  int _nextId = 0;

  @override
  void initState() {
    super.initState();
    _assembled = widget.text;
    if (widget.text.isNotEmpty) {
      _chunks.add(_Chunk(widget.text, id: _nextId++, settled: true));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (animationsDisabled(context)) {
      _flushQueue(settleAll: true);
    }
  }

  @override
  void didUpdateWidget(StreamingFadeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isStreaming) {
      _flushQueue(settleAll: true);
    }
    if (oldWidget.text != widget.text) {
      _onTextChanged(widget.text);
    }
  }

  void _onTextChanged(String next) {
    final visible = _assembled + _queued;
    if (next == visible) return;
    if (next.isEmpty) {
      _chunks.clear();
      _assembled = '';
      _queued = '';
      return;
    }
    if (!next.startsWith(visible)) {
      _queued = '';
      _assembled = next;
      _chunks
        ..clear()
        ..add(_Chunk(next, id: _nextId++, settled: true));
      return;
    }
    _queued += next.substring(visible.length);
  }

  void _flushQueue({bool settleAll = false}) {
    if (_queued.isEmpty) {
      if (settleAll) {
        for (final chunk in _chunks) {
          chunk.settled = true;
        }
      }
      return;
    }
    final delta = _queued;
    _queued = '';
    final start = _assembled.length;
    _assembled += delta;
    final ranges = _codeRanges(_assembled);
    _settleOverlappingCode(ranges);
    _splitAndAdd(delta, start, ranges);
    if (settleAll) {
      for (final chunk in _chunks) {
        chunk.settled = true;
      }
    }
  }

  /// Closing a fence/backtick can newly cover prose that already started
  /// fading. Mark those chunks settled without changing their text.
  void _settleOverlappingCode(List<_IntRange> ranges) {
    var offset = 0;
    for (final chunk in _chunks) {
      final end = offset + chunk.text.length;
      if (!chunk.settled && _overlapsCode(ranges, offset, end)) {
        chunk.settled = true;
        chunk.isCode = true;
      }
      offset = end;
    }
  }

  void _splitAndAdd(String delta, int absStart, List<_IntRange> ranges) {
    var i = 0;
    while (i < delta.length) {
      final abs = absStart + i;
      final covering = _covering(ranges, abs);
      if (covering != null) {
        final end = math.min(covering.end - absStart, delta.length);
        final piece = delta.substring(i, end);
        if (piece.isNotEmpty) {
          _chunks.add(_Chunk(piece, id: _nextId++, settled: true, isCode: true));
        }
        i = end;
      } else {
        final nextCode = _nextRangeStart(ranges, abs);
        var end = nextCode == null ? delta.length : math.min(nextCode - absStart, delta.length);
        end = surrogateSafeLength(delta, end);
        if (end <= i) {
          end = math.min(delta.length, i + 2);
        }
        if (end <= i) break;
        _addProse(delta.substring(i, end));
        i = end;
      }
    }
  }

  /// Only the last token of the last line fades. Newlines stay settled
  /// [TextSpan]s so a fading [WidgetSpan] is never a multi-line box.
  void _addProse(String piece) {
    if (piece.isEmpty) return;
    final lines = piece.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) {
        _chunks.add(_Chunk('\n', id: _nextId++, settled: true));
      }
      _addProseLine(lines[i], fade: i == lines.length - 1);
    }
  }

  void _addProseLine(String line, {required bool fade}) {
    if (line.isEmpty) return;
    if (!fade || line.trim().isEmpty) {
      _chunks.add(_Chunk(line, id: _nextId++, settled: true));
      return;
    }
    final split = _trailingTokenStart(line);
    final head = line.substring(0, split);
    var tail = line.substring(split);
    if (tail.length > _maxAnimatingChars) {
      final cut = surrogateSafeLength(tail, tail.length - _maxAnimatingChars);
      _chunks.add(_Chunk(head + tail.substring(0, cut), id: _nextId++, settled: true));
      tail = tail.substring(cut);
    } else if (head.isNotEmpty) {
      _chunks.add(_Chunk(head, id: _nextId++, settled: true));
    }
    if (tail.isNotEmpty) {
      _chunks.add(_Chunk(tail, id: _nextId++));
    }
  }

  /// Index where the last whitespace-separated token begins (including its
  /// leading whitespace). 0 if [piece] is a single token.
  int _trailingTokenStart(String piece) {
    final match = RegExp(r'\s+\S+\s*$').firstMatch(piece);
    if (match == null) return 0;
    return match.start;
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final scaler = MediaQuery.textScalerOf(context).clamp(
      minScaleFactor: 0.8,
      maxScaleFactor: 2.0,
    );
    final skipFade = !widget.isStreaming || animationsDisabled(context);
    _flushQueue(settleAll: skipFade);

    if (skipFade) {
      return Text.rich(
        TextSpan(text: widget.text, style: style),
        textScaler: scaler,
      );
    }

    final children = <InlineSpan>[];
    final buffer = StringBuffer();
    void flushSettled({bool beforeFade = false}) {
      if (buffer.isEmpty) return;
      var settledText = buffer.toString();
      buffer.clear();
      if (beforeFade) {
        var breaks = 0;
        while (settledText.endsWith('\n')) {
          settledText = settledText.substring(0, settledText.length - 1);
          breaks++;
        }
        if (settledText.isNotEmpty) {
          children.add(TextSpan(text: settledText, style: style));
        }
        for (var i = 0; i < breaks; i++) {
          children.add(_forcedLineBreak);
        }
        return;
      }
      children.add(TextSpan(text: settledText, style: style));
    }

    for (final chunk in _chunks) {
      if (chunk.settled || chunk.isCode) {
        buffer.write(chunk.text);
      } else {
        flushSettled(beforeFade: true);
        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: _FadeChunk(
              key: ValueKey<int>(chunk.id),
              text: chunk.text,
              style: style,
              textScaler: scaler,
              duration: widget.duration,
              onSettled: () {
                if (!mounted) return;
                setState(() => chunk.settled = true);
              },
            ),
          ),
        );
      }
    }
    flushSettled();

    return Text.rich(
      TextSpan(style: style, children: children),
      textScaler: scaler,
    );
  }
}

class _FadeChunk extends StatefulWidget {
  const _FadeChunk({
    super.key,
    required this.text,
    required this.style,
    required this.textScaler,
    required this.duration,
    required this.onSettled,
  });

  final String text;
  final TextStyle? style;
  final TextScaler textScaler;
  final Duration duration;
  final VoidCallback onSettled;

  @override
  State<_FadeChunk> createState() => _FadeChunkState();
}

class _FadeChunkState extends State<_FadeChunk> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        widget.onSettled();
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Text(
        widget.text,
        style: widget.style,
        textScaler: widget.textScaler,
        softWrap: false,
        maxLines: 1,
        overflow: TextOverflow.visible,
      ),
    );
  }
}

class _Chunk {
  _Chunk(
    this.text, {
    required this.id,
    this.settled = false,
    this.isCode = false,
  });

  final int id;
  String text;
  bool settled;
  bool isCode;
}

class _IntRange {
  const _IntRange(this.start, this.end);
  final int start;
  final int end;
}

List<_IntRange> _codeRanges(String text) {
  final ranges = <_IntRange>[];
  var i = 0;
  while (i < text.length) {
    if (text.startsWith('```', i)) {
      final close = text.indexOf('```', i + 3);
      if (close == -1) {
        ranges.add(_IntRange(i, text.length));
        break;
      }
      ranges.add(_IntRange(i, close + 3));
      i = close + 3;
      continue;
    }
    if (text.codeUnitAt(i) == 0x60) {
      final newline = text.indexOf('\n', i + 1);
      final lineEnd = newline == -1 ? text.length : newline;
      final close = text.indexOf('`', i + 1);
      if (close == -1 || close > lineEnd) {
        // Unclosed on this line — don't fade the remainder of the line.
        ranges.add(_IntRange(i, lineEnd));
        i = lineEnd;
        continue;
      }
      ranges.add(_IntRange(i, close + 1));
      i = close + 1;
      continue;
    }
    i++;
  }
  return ranges;
}

_IntRange? _covering(List<_IntRange> ranges, int index) {
  for (final range in ranges) {
    if (index >= range.start && index < range.end) return range;
  }
  return null;
}

int? _nextRangeStart(List<_IntRange> ranges, int index) {
  int? next;
  for (final range in ranges) {
    if (range.start >= index && (next == null || range.start < next)) {
      next = range.start;
    }
  }
  return next;
}

bool _overlapsCode(List<_IntRange> ranges, int start, int end) {
  for (final range in ranges) {
    if (range.start < end && range.end > start) return true;
  }
  return false;
}
