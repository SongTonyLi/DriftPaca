import 'dart:async';

import 'package:flutter/material.dart';

class ChatSelectModelButton extends StatelessWidget {
  final String? currentModelName;
  final void Function() onPressed;

  const ChatSelectModelButton({
    super.key,
    this.currentModelName,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final current = currentModelName;
    return TextButton.icon(
      icon: const Icon(Icons.auto_awesome_outlined),
      label: current != null ? Text(current) : const _RotatingModelHint(),
      iconAlignment: IconAlignment.end,
      onPressed: onPressed,
    );
  }
}

class _RotatingModelHint extends StatefulWidget {
  const _RotatingModelHint();

  @override
  State<_RotatingModelHint> createState() => _RotatingModelHintState();
}

class _RotatingModelHintState extends State<_RotatingModelHint> {
  // Ordered so adjacent names zigzag long/short with the smallest possible
  // length gaps (max gap = 4 chars, which is optimal given 'ministral' at 9).
  static const List<String> _names = [
    'kimi',       // 4
    'deepseek',   // 8
    'gemma',      // 5
    'ministral',  // 9
    'gemini',     // 6
    'nemotron',   // 8
    'qwen',       // 4
    'gpt-oss',    // 7
    'glm',        // 3
    'minimax',    // 7
  ];

  // The widest entry in [_names]. Used as an invisible sizer so the slot
  // never resizes as different-length names cycle through.
  static const String _widestName = 'ministral';

  static const String _leadingText = 'Click Here and Select ';
  static const String _trailingText = ' to start';

  static const Duration _interval = Duration(milliseconds: 1700);
  static const Duration _textTransition = Duration(milliseconds: 320);

  Timer? _ticker;
  int _index = 0;
  double? _phraseWidth;
  double? _nameSlotWidth;
  TextStyle? _measuredBase;
  TextScaler? _measuredScaler;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(_interval, (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % _names.length);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    final styleUnchanged = _measuredBase != null &&
        _measuredBase!.fontSize == base.fontSize &&
        _measuredBase!.fontWeight == base.fontWeight &&
        _measuredBase!.fontFamily == base.fontFamily &&
        _measuredBase!.letterSpacing == base.letterSpacing;
    if (styleUnchanged && _measuredScaler == scaler && _phraseWidth != null) {
      return;
    }
    _measuredBase = base;
    _measuredScaler = scaler;
    final bold = base.copyWith(fontWeight: FontWeight.w600);
    _nameSlotWidth = _measure(_widestName, bold, scaler) + 16; // slot breathing
    _phraseWidth = _measure(_leadingText, base, scaler) +
        _nameSlotWidth! +
        _measure(_trailingText, base, scaler) +
        24; // extra breathing room around the label
  }

  double _measure(String text, TextStyle style, TextScaler scaler) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    return tp.size.width;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = DefaultTextStyle.of(context).style;
    final highlightStyle = baseStyle.copyWith(fontWeight: FontWeight.w600);
    final currentName = _names[_index];

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(_leadingText),
        Stack(
          alignment: Alignment.center,
          children: [
            // Invisible sizer: locks the slot to the width of the longest
            // name (plus breathing room) so cycling never reflows surrounding
            // text and short names still feel spacious.
            Visibility(
              visible: false,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: SizedBox(
                width: _nameSlotWidth,
                child: Text(
                  _widestName,
                  style: highlightStyle,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: _textTransition,
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) {
                final slide = Tween<Offset>(
                  begin: const Offset(0, 0.35),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child: Text(
                currentName,
                key: ValueKey<String>(currentName),
                style: highlightStyle,
              ),
            ),
          ],
        ),
        const Text(_trailingText),
      ],
    );

    final width = _phraseWidth;
    if (width == null) return row;
    return SizedBox(width: width, child: Center(child: row));
  }
}
