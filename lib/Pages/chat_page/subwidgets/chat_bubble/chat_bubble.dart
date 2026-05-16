import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
import 'chat_bubble_menu.dart';
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
    final actions = ChatBubbleActions(message);
    final isUser = message.role == OllamaMessageRole.user;

    return ChatBubbleMenu(
      menuChildren: [
        MenuItemButton(
          onPressed: actions.handleCopy,
          leadingIcon: Icon(Icons.copy_outlined),
          child: const Text('Copy'),
        ),
        if (isUser) ...[
          MenuItemButton(
            onPressed: () => actions.handleEdit(context),
            closeOnActivate: false,
            leadingIcon: Icon(Icons.edit_outlined),
            child: const Text('Edit'),
          ),
        ],
        if (!isUser)
          MenuItemButton(
            onPressed: () => actions.handleRegenerate(context),
            leadingIcon: Icon(Icons.refresh_outlined),
            child: const Text('Regenerate'),
          ),
        Divider(),
        MenuItemButton(
          onPressed: () => actions.handleDelete(context),
          leadingIcon: Icon(Icons.delete_outline),
          child: const Text('Delete'),
        ),
      ],
      child: _ChatBubbleBody(message: message, isStreaming: isStreaming),
    );
  }
}

class _ChatBubbleBody extends StatelessWidget {
  final OllamaMessage message;
  final bool isStreaming;

  const _ChatBubbleBody({required this.message, required this.isStreaming});

  bool get isSentFromUser => message.role == OllamaMessageRole.user;

  CrossAxisAlignment get bubbleAlignment =>
      isSentFromUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: isSentFromUser ? 64.0 : 16.0,
        right: isSentFromUser ? 8.0 : 16.0,
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
                children: message.images!
                    .map((imageFile) => ChatBubbleImage(imageFile: imageFile))
                    .toList(),
              ),
            ),
          if (isSentFromUser)
            _UserBubble(message: message, buildMarkdown: _buildMarkdown)
          else
            _AssistantBubble(
              message: message,
              isStreaming: isStreaming,
              buildMarkdown: _buildMarkdown,
            ),
        ],
      ),
    );
  }

  static Widget _buildMarkdown(BuildContext context, String data) {
    return MarkdownBody(
      data: _preprocessLatex(data),
      selectable: true,
      softLineBreak: true,
      styleSheet: context.markdownStyleSheet,
      syntaxHighlighter: CodeSyntaxHighlighter(
        brightness: Theme.of(context).brightness,
      ),
      extensionSet: md.ExtensionSet.gitHubFlavored,
      builders: {
        'latex': LatexElementBuilder(),
        'latexBlock': _CenteredLatexBuilder(),
      },
      inlineSyntaxes: [LatexInlineSyntax()],
      blockSyntaxes: [LatexBlockSyntax()],
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
    text = text.replaceAllMapped(
      RegExp(r'\\\[([\s\S]*?)\\\]'),
      (m) => '\$\$${m[1]}\$\$',
    );
    text = text.replaceAllMapped(
      RegExp(r'\\\((.+?)\\\)'),
      (m) => '\$${m[1]}\$',
    );
    return text;
  }
}

class _UserBubble extends StatelessWidget {
  final OllamaMessage message;
  final Widget Function(BuildContext, String) buildMarkdown;

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
  final Widget Function(BuildContext, String) buildMarkdown;

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

    if (widget.message.thinking != null &&
        widget.message.thinking!.isNotEmpty) {
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
        _ActionChip(
          icon: Icons.copy_outlined,
          label: 'Copy',
          color: colorScheme.onSurfaceVariant,
          onTap: actions.handleCopy,
        ),
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

/// Renders block LaTeX ($$...$$) centered with display math style.
class _CenteredLatexBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final text = element.textContent;
    if (text.isEmpty) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        width: double.infinity,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Center(
            child: Math.tex(
              text,
              mathStyle: MathStyle.display,
              textStyle: preferredStyle,
            ),
          ),
        ),
      ),
    );
  }
}
