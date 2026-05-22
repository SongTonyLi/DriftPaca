import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:llamaseek/Providers/chat_provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_markdown_latex/flutter_markdown_latex.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:llamaseek/Extensions/code_syntax_highlighter.dart';
import 'package:llamaseek/Extensions/markdown_stylesheet_extension.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'chat_bubble_actions.dart';
import 'chat_bubble_image.dart';
import 'chat_bubble_think_block.dart' show ThinkBlockParser, ThinkBlockWidget;
import 'streaming_llama.dart';

class ChatBubble extends StatelessWidget {
  final OllamaMessage message;
  final bool isStreaming;

  const ChatBubble({
    super.key,
    required this.message,
    this.isStreaming = false,
  });

  @override
  Widget build(BuildContext context) {
    return _ChatBubbleBody(message: message, isStreaming: isStreaming);
  }
}

class _ChatBubbleBody extends StatelessWidget {
  final OllamaMessage message;
  final bool isStreaming;

  const _ChatBubbleBody({required this.message, required this.isStreaming});

  static final md.ExtensionSet _markdownExtensionSet = md.ExtensionSet(
    [
      ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
      LatexBlockSyntax(),
    ],
    [
      _InlineHtmlBrSyntax(),
      _InlineLatexSyntax(),
      ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
    ],
  );

  bool get isSentFromUser => message.role == OllamaMessageRole.user;

  CrossAxisAlignment get bubbleAlignment => isSentFromUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: isSentFromUser ? 48.0 : 14.0,
        right: isSentFromUser ? 8.0 : 14.0,
        top: 3.0,
        bottom: 3.0,
      ),
      child: Column(
        crossAxisAlignment: bubbleAlignment,
        children: [
          if (message.images != null && message.images!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: message.images!.asMap().entries.map((entry) => ChatBubbleImage(
                  imageFile: entry.value,
                  allImages: message.images!,
                  index: entry.key,
                )).toList(),
              ),
            ),
          if (isSentFromUser) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                TimeOfDay.fromDateTime(message.createdAt).format(context),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  fontSize: 11,
                ),
              ),
            ),
            _UserBubble(message: message, buildMarkdown: _buildMarkdown),
            _UserActionButtons(message: message),
          ] else
            _AssistantBubble(
              message: message,
              isStreaming: isStreaming,
              buildMarkdown: _buildMarkdown,
            ),
        ],
      ),
    );
  }

  static Widget _buildMarkdown(BuildContext context, String data, {bool selectable = false}) {
    return MarkdownBody(
      data: _escapeLatexPipesInTables(_preprocessLatex(_unwrapLatexCodeFences(data))),
      selectable: selectable,
      softLineBreak: true,
      styleSheet: context.markdownStyleSheet,
      syntaxHighlighter: CodeSyntaxHighlighter(
        brightness: Theme.of(context).brightness,
      ),
      extensionSet: _markdownExtensionSet,
      builders: {
        'latex': _SmartLatexBuilder(),
        'br': _HtmlBrBuilder(),
      },
      onTapLink: (text, href, title) => launchUrlString(href!),
    );
  }

  /// Unwraps code fences with language tag `latex`, `math`, or `markdown`
  /// so their content is rendered as markdown/LaTeX instead of raw code.
  /// Some models (e.g. gemma3, qwen3) wrap LaTeX output in these fences.
  static String _unwrapLatexCodeFences(String content) {
    return content.replaceAllMapped(
      RegExp(r'```(?:latex|math|markdown)\s*\n([\s\S]*?)```', multiLine: true),
      (m) => m.group(1)!,
    );
  }

  /// Converts \(...\) to $...$ and \[...\] to $$...$$ for LaTeX parsing,
  /// skipping content inside code fences and inline code.
  static String _preprocessLatex(String content) {
    final buffer = StringBuffer();
    int pos = 0;
    final codePattern = RegExp(r'```[\s\S]*?```|`[^`\n]+`');
    for (final match in codePattern.allMatches(content)) {
      buffer.write(_replaceLatexDelimiters(content.substring(pos, match.start)));
      buffer.write(match.group(0));
      pos = match.end;
    }
    buffer.write(_replaceLatexDelimiters(content.substring(pos)));
    return buffer.toString();
  }

  static String _replaceLatexDelimiters(String text) {
    // Convert \[...\] to $$...$$ (only when both delimiters present)
    text = text.replaceAllMapped(
      RegExp(r'\\\[([\s\S]*?)\\\]'),
      (m) => '\$\$${m[1]}\$\$',
    );
    // Convert \(...\) to $...$
    text = text.replaceAllMapped(
      RegExp(r'\\\((.+?)\\\)'),
      (m) => '\$${m[1]}\$',
    );
    return text;
  }

  /// In table rows, replaces `|` inside LaTeX ($...$, $$...$$) with
  /// `\vert` so the markdown table parser doesn't split cells on them.
  ///
  /// The challenge: `|` is both a table cell delimiter AND valid LaTeX
  /// (absolute value). A naive regex on the full line would false-match
  /// currency like `$5 | $10` as one LaTeX expression.
  ///
  /// Guard: when a match contains `|`, we check whether the inner
  /// content (with pipes stripped) is purely numeric/currency-like
  /// (digits, spaces, punctuation). If so, the `$` signs are currency
  /// and the `|` is a cell delimiter — skip replacement.
  static String _escapeLatexPipesInTables(String content) {
    final lines = content.split('\n');
    final result = <String>[];
    // Same pattern as _InlineLatexSyntax for consistency.
    final latexPattern = RegExp(r'\$\$(.+?)\$\$|\$([^$\n]+?)\$');
    final codePattern = RegExp(r'`[^`\n]+`');

    for (final line in lines) {
      if (!line.trimLeft().startsWith('|')) {
        result.add(line);
        continue;
      }

      // Skip inline code, only process non-code segments.
      final buf = StringBuffer();
      int pos = 0;
      for (final codeMatch in codePattern.allMatches(line)) {
        buf.write(_replacePipesInLatex(line.substring(pos, codeMatch.start), latexPattern));
        buf.write(codeMatch.group(0));
        pos = codeMatch.end;
      }
      buf.write(_replacePipesInLatex(line.substring(pos), latexPattern));

      result.add(buf.toString());
    }

    return result.join('\n');
  }

  /// Regex for content that looks like currency/numeric, NOT LaTeX.
  /// Digits, whitespace, and common punctuation (no letters).
  static final _currencyContentPattern = RegExp(r'^[\d\s,.\-+%/()]*$');

  /// Within matched $...$ / $$...$$ regions, replace || with \Vert
  /// and remaining | with \vert — but skip if the inner content is
  /// purely numeric (likely currency like `$5 | $10`, not LaTeX).
  static String _replacePipesInLatex(String text, RegExp pattern) {
    return text.replaceAllMapped(pattern, (match) {
      final full = match.group(0)!;
      if (!full.contains('|')) return full;

      // Guard: if inner content without pipes is purely numeric/currency,
      // this is `$5 | $10` not LaTeX — leave the | as cell delimiters.
      final inner = (match.group(1) ?? match.group(2) ?? '').replaceAll('|', '');
      if (_currencyContentPattern.hasMatch(inner.trim())) return full;

      // Real LaTeX — escape || (norm) first, then single |.
      var escaped = full.replaceAllMapped(RegExp(r'(?<!\\)\|\|'), (_) => '\\Vert ');
      escaped = escaped.replaceAllMapped(RegExp(r'(?<!\\)\|'), (_) => '\\vert ');
      return escaped;
    });
  }
}

class _UserBubble extends StatelessWidget {
  final OllamaMessage message;
  final Widget Function(BuildContext, String, {bool selectable}) buildMarkdown;

  const _UserBubble({required this.message, required this.buildMarkdown});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primaryContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20.0),
          topRight: Radius.circular(20.0),
          bottomLeft: Radius.circular(20.0),
          bottomRight: Radius.circular(4.0),
        ),
      ),
      child: buildMarkdown(context, message.content),
    );
  }
}

class _AssistantBubble extends StatefulWidget {
  final OllamaMessage message;
  final bool isStreaming;
  final Widget Function(BuildContext, String, {bool selectable}) buildMarkdown;

  const _AssistantBubble({
    required this.message,
    required this.isStreaming,
    required this.buildMarkdown,
  });

  @override
  State<_AssistantBubble> createState() => _AssistantBubbleState();
}

class _AssistantBubbleState extends State<_AssistantBubble>
    with SingleTickerProviderStateMixin {
  bool _wasStreaming = false;

  // ── Typewriter reveal state ──
  /// The full accumulated content from the provider (grows as tokens arrive).
  String _targetContent = '';

  /// How many characters of [_targetContent] are currently visible.
  int _revealedLength = 0;

  /// Ticker driving the character-by-character reveal animation.
  Ticker? _revealTicker;

  /// Fractional character position — allows sub-character-per-frame pacing
  /// for smoother speed transitions.
  double _revealProgress = 0.0;

  /// Base characters to reveal per frame at 60fps (~40 chars/sec).
  /// Slow enough to see the typing effect, fast enough to feel responsive.
  static const double _baseCharsPerFrame = 0.7;

  /// When the unrevealed buffer exceeds this threshold, the reveal speed
  /// ramps up proportionally to prevent falling behind.
  static const int _catchUpThreshold = 80;

  @override
  void didUpdateWidget(_AssistantBubble old) {
    super.didUpdateWidget(old);
    if (old.isStreaming && !widget.isStreaming) {
      // Streaming just ended — reveal all remaining content instantly.
      _wasStreaming = true;
      _targetContent = widget.message.content;
      _revealedLength = _targetContent.length;
      _revealProgress = _revealedLength.toDouble();
      _stopRevealTicker();
    } else if (widget.isStreaming) {
      // New tokens arrived — update target and ensure ticker is running.
      _targetContent = widget.message.content;
      _ensureRevealTicker();
    } else {
      _targetContent = widget.message.content;
      _revealedLength = _targetContent.length;
      _revealProgress = _revealedLength.toDouble();
    }
  }

  void _ensureRevealTicker() {
    if (_revealTicker != null) return;
    _revealTicker = createTicker(_onRevealTick)..start();
  }

  void _stopRevealTicker() {
    _revealTicker?.stop();
    _revealTicker?.dispose();
    _revealTicker = null;
  }

  void _onRevealTick(Duration elapsed) {
    if (_revealedLength >= _targetContent.length) {
      // Caught up — pause ticker until new content arrives.
      _stopRevealTicker();
      return;
    }

    final remaining = _targetContent.length - _revealedLength;
    // Adaptive speed: ramp up when buffer is large to prevent falling behind.
    final speed = remaining > _catchUpThreshold
        ? _baseCharsPerFrame + (remaining - _catchUpThreshold) * 0.5
        : _baseCharsPerFrame;

    _revealProgress += speed;
    final newLength = _revealProgress.floor().clamp(0, _targetContent.length);

    if (newLength != _revealedLength) {
      setState(() {
        _revealedLength = newLength;
      });
    }
  }

  @override
  void dispose() {
    _stopRevealTicker();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMessageContent(context),
          // Llama on its own line: running during streaming, resting after
          if (widget.isStreaming || _wasStreaming)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 2),
              child: StreamingLlama(isRunning: widget.isStreaming),
            ),
          // Smoothly reveal action buttons when streaming ends
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            child: widget.isStreaming
                ? const SizedBox(width: double.infinity, height: 0)
                : Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _AssistantActionButtons(message: widget.message),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, String data) {
    return widget.buildMarkdown(context, data);
  }

  Widget _buildModelLabel(BuildContext context) {
    final model = widget.message.model;
    if (model == null || model.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        model,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildMessageContent(BuildContext context) {
    final content = widget.isStreaming
        ? _targetContent.substring(0, _revealedLength)
        : widget.message.content;

    if (widget.message.thinking != null && widget.message.thinking!.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildModelLabel(context),
          ThinkBlockWidget(
            content: widget.message.thinking!,
            isComplete: content.isNotEmpty,
            isStreaming: widget.isStreaming,
          ),
          if (content.isNotEmpty) ...[
            const SizedBox(height: 4),
            _buildContent(context, content),
          ],
        ],
      );
    }

    final parsed = ThinkBlockParser.tryParse(content);

    if (parsed != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildModelLabel(context),
          ThinkBlockWidget(
            content: parsed.thinkContent,
            isComplete: parsed.isThinkingComplete,
            isStreaming: widget.isStreaming,
          ),
          if (parsed.responseContent.isNotEmpty) ...[
            const SizedBox(height: 4),
            _buildContent(context, parsed.responseContent),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildModelLabel(context),
        _buildContent(context, content),
      ],
    );
  }
}

/// Copy and Edit buttons shown below user messages.
class _UserActionButtons extends StatelessWidget {
  final OllamaMessage message;

  const _UserActionButtons({required this.message});

  @override
  Widget build(BuildContext context) {
    final actions = ChatBubbleActions(message);
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CopyChip(onCopy: actions.handleCopy),
        const SizedBox(width: 8),
        _ActionChip(
          icon: Icons.edit_outlined,
          label: 'Edit',
          color: colorScheme.onSurfaceVariant,
          onTap: () async {
            final result = await _showEditPopup(context, message);
            if (result != null && context.mounted) {
              final chatProvider = Provider.of<ChatProvider>(context, listen: false);
              chatProvider.editAndResend(message, result);
            }
          },
        ),
      ],
    );
  }
}

/// Copy and Regenerate buttons shown below assistant messages.
class _AssistantActionButtons extends StatelessWidget {
  final OllamaMessage message;

  const _AssistantActionButtons({required this.message});

  @override
  Widget build(BuildContext context) {
    final actions = ChatBubbleActions(message);
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CopyChip(onCopy: actions.handleCopy),
        const SizedBox(width: 8),
        _ActionChip(
          icon: Icons.refresh_outlined,
          label: 'Regenerate',
          color: colorScheme.onSurfaceVariant,
          onTap: () => actions.handleRegenerate(context),
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Copy chip that shows "Copied" feedback with checkmark for 3 seconds.
class _CopyChip extends StatefulWidget {
  final VoidCallback onCopy;

  const _CopyChip({required this.onCopy});

  @override
  State<_CopyChip> createState() => _CopyChipState();
}

class _CopyChipState extends State<_CopyChip> with SingleTickerProviderStateMixin {
  bool _copied = false;

  void _handleTap() {
    widget.onCopy();
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = _copied ? colorScheme.primary : colorScheme.onSurfaceVariant;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: InkWell(
        key: ValueKey(_copied),
        onTap: _handleTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _copied ? Icons.check_rounded : Icons.copy_outlined,
                size: 15,
                color: color,
              ),
              const SizedBox(width: 4),
              Text(
                _copied ? 'Copied' : 'Copy',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: _copied ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows an animated edit popup that expands from the chat bubble.
/// Returns the edited text if saved, null if cancelled.
Future<String?> _showEditPopup(BuildContext context, OllamaMessage message) async {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (dialogContext, animation, secondaryAnimation, _) {
      final moveCurve = CurvedAnimation(
        parent: animation,
        curve: const Cubic(0.16, 1.0, 0.3, 1.0),
        reverseCurve: Curves.easeInQuart,
      );
      final fadeCurve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      );

      return FadeTransition(
        opacity: fadeCurve,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(moveCurve),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(moveCurve),
            child: _EditPopupContent(message: message),
          ),
        ),
      );
    },
  );
}

class _EditPopupContent extends StatefulWidget {
  final OllamaMessage message;

  const _EditPopupContent({required this.message});

  @override
  State<_EditPopupContent> createState() => _EditPopupContentState();
}

class _EditPopupContentState extends State<_EditPopupContent> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.message.content);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: colorScheme.outline.withValues(alpha: 0.15),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                          child: TextField(
                            controller: _controller,
                            autofocus: true,
                            maxLines: null,
                            textCapitalization: TextCapitalization.sentences,
                            style: Theme.of(context).textTheme.bodyLarge,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Edit message...',
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  color: colorScheme.onPrimaryContainer.withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: () {
                                final text = _controller.text.trim();
                                if (text.isNotEmpty) {
                                  Navigator.pop(context, text);
                                }
                              },
                              icon: const Icon(Icons.send_rounded, size: 16),
                              label: const Text('Send as New'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Converts <br>, <br/>, <br /> into a `br` element rendered as a
/// full-width line break widget. Using a WidgetSpan (via _HtmlBrBuilder)
/// instead of a \n text node avoids a Flutter RichText issue where
/// WidgetSpan elements don't follow \n line breaks correctly — they
/// float to the previous line instead of staying with their text.
class _InlineHtmlBrSyntax extends md.InlineSyntax {
  _InlineHtmlBrSyntax() : super(r'<br\s*/?>');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.empty('br'));
    return true;
  }
}

/// Renders `br` elements as a full-width zero-height widget that
/// forces subsequent inline content to the next line.
class _HtmlBrBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return const SizedBox(width: double.infinity, height: 0);
  }
}

class _InlineLatexSyntax extends md.InlineSyntax {
  // Match $$...$$ (display) or $...$ (inline).
  // No restrictive lookahead — allows LaTeX inside bold, before dashes, etc.
  _InlineLatexSyntax() : super(r'\$\$([\s\S]+?)\$\$|\$([^$\n]+?)\$', startCharacter: 0x24);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final displayContent = match.group(1);
    final inlineContent = match.group(2);
    final equation = (displayContent ?? inlineContent)?.trim();

    // MUST always return true when regex matched — returning false
    // without consuming causes InlineParser to loop infinitely.
    if (equation == null || equation.isEmpty) {
      parser.addNode(md.Text(match.group(0)!));
      return true;
    }

    final isDisplay = displayContent != null;
    final element = md.Element.text('latex', equation);
    element.attributes['MathStyle'] = isDisplay ? 'display' : 'text';
    parser.addNode(element);
    return true;
  }
}

/// Renders LaTeX: inline ($...$) normally, display ($$...$$) centered.
///
/// For inline math, we return a [RichText] containing a [WidgetSpan] so that
/// flutter_markdown's `_mergeInlineChildren` merges it with adjacent text
/// spans into a single flowing [RichText]. Without this, the Math widget
/// becomes a separate child in a [Wrap] and breaks to its own line.
class _SmartLatexBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final text = element.textContent;
    if (text.isEmpty) return const SizedBox();

    final isDisplay = element.attributes['MathStyle'] == 'display';
    final rawSource = isDisplay ? '\$\$$text\$\$' : '\$$text\$';

    // Ensure text color is explicit — flutter_math_fork can render
    // invisible text when preferredStyle has no color (e.g. in tables).
    final effectiveColor = preferredStyle?.color ?? Theme.of(context).textTheme.bodyMedium?.color;
    final mathTextStyle = (preferredStyle ?? const TextStyle()).copyWith(color: effectiveColor);

    final mathWidget = _SmartLatexWidget(
      text: text,
      isDisplay: isDisplay,
      rawSource: rawSource,
      mathTextStyle: mathTextStyle,
    );

    if (isDisplay) return mathWidget;

    // Wrap inline math in RichText+WidgetSpan so it flows with surrounding
    // text instead of breaking to a new line in the Wrap layout.
    return RichText(
      text: TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: mathWidget,
          ),
        ],
      ),
    );
  }
}

class _SmartLatexWidget extends StatelessWidget {
  final String text;
  final bool isDisplay;
  final String rawSource;
  final TextStyle mathTextStyle;

  const _SmartLatexWidget({
    required this.text,
    required this.isDisplay,
    required this.rawSource,
    required this.mathTextStyle,
  });

  @override
  Widget build(BuildContext context) {
    final mathWidget = Math.tex(
      text,
      mathStyle: isDisplay ? MathStyle.display : MathStyle.text,
      textStyle: mathTextStyle,
      onErrorFallback: (_) => _LatexSourceFallback(
        rawSource: rawSource,
        isDisplay: isDisplay,
        preferredStyle: mathTextStyle,
      ),
    );

    if (isDisplay) {
      // Display math: centered, horizontally scrollable for long equations.
      // When inside a table cell, use _IntrinsicFriendlyClip to avoid
      // IntrinsicColumnWidth crashing on flutter_math_fork's LayoutBuilder.
      final inTableCell = context.findAncestorWidgetOfExactType<TableCell>() != null;
      if (inTableCell) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _IntrinsicFriendlyClip(child: mathWidget),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: SizedBox(
          width: double.infinity,
          child: Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.antiAlias,
              child: mathWidget,
            ),
          ),
        ),
      );
    }

    // Inline math in table cells: wrap in a scroll view that provides
    // stub intrinsic dimensions. flutter_math_fork's internal LayoutBuilder
    // cannot report intrinsics, but Table with IntrinsicColumnWidth requires
    // them — _IntrinsicFriendlyClip resolves this conflict.
    final inTableCell = context.findAncestorWidgetOfExactType<TableCell>() != null;
    if (inTableCell) {
      return _IntrinsicFriendlyClip(child: mathWidget);
    }

    // Inline math in text: return directly so it flows with surrounding
    // text. Wrapping in SingleChildScrollView breaks WidgetSpan intrinsic
    // width calculation, causing line breaks (e.g. "$N$ 体" splits).
    return mathWidget;
  }
}

/// A horizontally scrollable wrapper that provides stub intrinsic dimensions.
///
/// flutter_math_fork uses LayoutBuilder internally for certain complex
/// constructs (aligned, cases, matrices). LayoutBuilder cannot report intrinsic
/// dimensions. When these widgets are in a Table with IntrinsicColumnWidth,
/// the table's layout algorithm asks for intrinsic widths and crashes.
///
/// This widget solves the conflict by:
/// 1. Reporting a fixed intrinsic width (so the table gets a usable value)
/// 2. Allowing its child to scroll horizontally when wider than the cell
class _IntrinsicFriendlyClip extends SingleChildRenderObjectWidget {
  const _IntrinsicFriendlyClip({required Widget child}) : super(child: child);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderIntrinsicFriendlyClip();
}

class _RenderIntrinsicFriendlyClip extends RenderProxyBox {
  // Fallback intrinsic width when the child (flutter_math_fork) can't report.
  static const double _fallbackWidth = 50.0;

  double _safeChildIntrinsic(double height, {required bool min}) {
    try {
      final v = min
          ? child?.getMinIntrinsicWidth(height)
          : child?.getMaxIntrinsicWidth(height);
      return (v != null && v > 0) ? v : _fallbackWidth;
    } catch (_) {
      return _fallbackWidth;
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _safeChildIntrinsic(height, min: true);

  @override
  double computeMaxIntrinsicWidth(double height) {
    final minW = computeMinIntrinsicWidth(height);
    final maxW = _safeChildIntrinsic(height, min: false);
    // Table asserts max >= min.
    return maxW >= minW ? maxW : minW;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    try {
      return child?.getMinIntrinsicHeight(width) ?? 0;
    } catch (_) {
      return 20;
    }
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    try {
      return child?.getMaxIntrinsicHeight(width) ?? 0;
    } catch (_) {
      return 20;
    }
  }

  @override
  void performLayout() {
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    // Let child lay out with unbounded width so math isn't clipped.
    child!.layout(
      BoxConstraints(
        maxWidth: double.infinity,
        maxHeight: constraints.maxHeight,
      ),
      parentUsesSize: true,
    );
    // Our own size respects the incoming constraints (table cell width).
    size = constraints.constrain(child!.size);
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    // Clip to our size — child may be wider.
    context.pushClipRect(needsCompositing, offset, Offset.zero & size, (context, offset) {
      context.paintChild(child!, offset);
    });
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (child == null) return false;
    return child!.hitTest(result, position: position);
  }
}

class _LatexSourceFallback extends StatelessWidget {
  final String rawSource;
  final bool isDisplay;
  final TextStyle? preferredStyle;

  const _LatexSourceFallback({
    required this.rawSource,
    required this.isDisplay,
    this.preferredStyle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final markdownStyleSheet = context.markdownStyleSheet;
    final textStyle = markdownStyleSheet.code
            ?.copyWith(
              backgroundColor: Colors.transparent,
              color: colorScheme.onSurface.withValues(alpha: 0.82),
            )
            .merge(
              preferredStyle?.copyWith(
                backgroundColor: Colors.transparent,
                color: colorScheme.onSurface.withValues(alpha: 0.82),
              ),
            ) ??
        preferredStyle?.copyWith(
          color: colorScheme.onSurface.withValues(alpha: 0.82),
        );

    if (isDisplay) {
      // Do NOT use width: double.infinity here — this fallback can be rendered
      // inside a horizontal SingleChildScrollView (from _SmartLatexWidget's
      // display mode), which provides unbounded width constraints.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: DecoratedBox(
          decoration: markdownStyleSheet.codeblockDecoration ?? const BoxDecoration(),
          child: Padding(
            padding: markdownStyleSheet.codeblockPadding ?? const EdgeInsets.all(14),
            child: Text(rawSource, style: textStyle),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Text(rawSource, style: textStyle),
      ),
    );
  }
}
