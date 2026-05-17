import 'dart:ui';

import 'package:flutter/material.dart';
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
                children: message.images!.map((imageFile) => ChatBubbleImage(imageFile: imageFile)).toList(),
              ),
            ),
          if (isSentFromUser) ...[
            _UserBubble(message: message, buildMarkdown: _buildMarkdown),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _UserActionButtons(message: message),
            ),
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
      data: _preprocessLatex(data),
      selectable: selectable,
      softLineBreak: true,
      styleSheet: context.markdownStyleSheet,
      syntaxHighlighter: CodeSyntaxHighlighter(
        brightness: Theme.of(context).brightness,
      ),
      extensionSet: _markdownExtensionSet,
      builders: {
        'latex': _SmartLatexBuilder(),
      },
      onTapLink: (text, href, title) => launchUrlString(href!),
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

class _AssistantBubbleState extends State<_AssistantBubble> {
  bool _wasStreaming = false;
  String _throttledContent = '';
  bool _updatePending = false;

  @override
  void didUpdateWidget(_AssistantBubble old) {
    super.didUpdateWidget(old);
    if (old.isStreaming && !widget.isStreaming) {
      _wasStreaming = true;
      _throttledContent = widget.message.content;
      _updatePending = false;
    } else if (widget.isStreaming) {
      _scheduleContentUpdate();
    } else {
      _throttledContent = widget.message.content;
    }
  }

  void _scheduleContentUpdate() {
    if (_updatePending) return;
    _updatePending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _throttledContent = widget.message.content;
          _updatePending = false;
        });
      }
    });
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

  Widget _buildMessageContent(BuildContext context) {
    final content = widget.isStreaming ? _throttledContent : widget.message.content;

    if (widget.message.thinking != null && widget.message.thinking!.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ThinkBlockWidget(
            content: widget.message.thinking!,
            isComplete: content.isNotEmpty,
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
          ThinkBlockWidget(
            content: parsed.thinkContent,
            isComplete: parsed.isThinkingComplete,
          ),
          if (parsed.responseContent.isNotEmpty) ...[
            const SizedBox(height: 4),
            _buildContent(context, parsed.responseContent),
          ],
        ],
      );
    }

    return _buildContent(context, content);
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
              actions.handleRegenerate(context);
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
Future<String?> _showEditPopup(BuildContext context, OllamaMessage message) async {
  final chatProvider = Provider.of<ChatProvider>(context, listen: false);

  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (dialogContext, animation, secondaryAnimation, _) {
      // iOS-like smooth deceleration for movement and scale
      final moveCurve = CurvedAnimation(
        parent: animation,
        curve: const Cubic(0.16, 1.0, 0.3, 1.0),
        reverseCurve: Curves.easeInQuart,
      );
      // Fade completes faster so content is visible while still settling
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
            child: _EditPopupContent(
              message: message,
              chatProvider: chatProvider,
            ),
          ),
        ),
      );
    },
  );
}

class _EditPopupContent extends StatefulWidget {
  final OllamaMessage message;
  final ChatProvider chatProvider;

  const _EditPopupContent({
    required this.message,
    required this.chatProvider,
  });

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
              filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
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
                    // Text field
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
                    // Action buttons
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
                            onPressed: () async {
                              final text = _controller.text.trim();
                              if (text.isNotEmpty) {
                                await widget.chatProvider.updateMessage(
                                  widget.message,
                                  newContent: text,
                                );
                                if (context.mounted) {
                                  Navigator.pop(context, text);
                                }
                              }
                            },
                            icon: const Icon(Icons.send_rounded, size: 16),
                            label: const Text('Save & Resend'),
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

class _InlineLatexSyntax extends md.InlineSyntax {
  // Match $$...$$ (display) or $...$ (inline).
  // No restrictive lookahead — allows LaTeX inside bold, before dashes, etc.
  _InlineLatexSyntax()
      : super(r'\$\$([\s\S]+?)\$\$|\$([^$\n]+?)\$', startCharacter: 0x24);

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
    final effectiveColor = preferredStyle?.color ??
        Theme.of(context).textTheme.bodyMedium?.color;
    final mathTextStyle = (preferredStyle ?? const TextStyle())
        .copyWith(color: effectiveColor);

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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: SizedBox(
          width: double.infinity,
          child: Center(child: mathWidget),
        ),
      );
    }

    // Return inline math directly — SingleChildScrollView breaks
    // IntrinsicColumnWidth in tables (reports zero width → invisible cells).
    return mathWidget;
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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Container(
          width: double.infinity,
          padding: markdownStyleSheet.codeblockPadding ?? const EdgeInsets.all(14),
          decoration: markdownStyleSheet.codeblockDecoration,
          child: Text(rawSource, style: textStyle),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Text(rawSource, style: textStyle),
        ),
      ),
    );
  }
}
