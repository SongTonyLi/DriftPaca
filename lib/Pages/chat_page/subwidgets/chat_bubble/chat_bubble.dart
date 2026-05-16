import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_markdown_latex/flutter_markdown_latex.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:llamaseek/Extensions/markdown_stylesheet_extension.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'chat_bubble_actions.dart';
import 'chat_bubble_image.dart';
import 'chat_bubble_menu.dart';
import 'chat_bubble_think_block.dart' show ThinkBlockParser, ThinkBlockWidget;
import 'streaming_text_renderer.dart';

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
      data: data,
      selectable: true,
      softLineBreak: true,
      styleSheet: context.markdownStyleSheet.copyWith(
        code: GoogleFonts.sourceCodePro(),
      ),
      extensionSet: md.ExtensionSet.gitHubFlavored,
      builders: {
        'latex': LatexElementBuilder(),
        'latexBlock': LatexElementBuilder(),
      },
      inlineSyntaxes: [LatexInlineSyntax()],
      blockSyntaxes: [LatexBlockSyntax()],
      onTapLink: (text, href, title) => launchUrlString(href!),
    );
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

class _AssistantBubble extends StatelessWidget {
  final OllamaMessage message;
  final bool isStreaming;
  final Widget Function(BuildContext, String) buildMarkdown;

  const _AssistantBubble({
    required this.message,
    required this.isStreaming,
    required this.buildMarkdown,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMessageContent(context),
          // Smoothly reveal action buttons when streaming ends
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            child: isStreaming
                ? const SizedBox(width: double.infinity, height: 0)
                : Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _AssistantActionButtons(message: message),
                  ),
          ),
        ],
      ),
    );
  }

  /// Chooses between animated streaming text or full markdown.
  Widget _buildContent(BuildContext context, String data) {
    if (isStreaming && data.isNotEmpty) {
      return StreamingTextRenderer(
        content: data,
        baseStyle: Theme.of(context).textTheme.bodyLarge,
      );
    }
    return buildMarkdown(context, data);
  }

  Widget _buildMessageContent(BuildContext context) {
    if (message.thinking != null && message.thinking!.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ThinkBlockWidget(
            content: message.thinking!,
            isComplete: message.content.isNotEmpty,
          ),
          if (message.content.isNotEmpty) ...[
            const SizedBox(height: 4),
            _buildContent(context, message.content),
          ],
        ],
      );
    }

    final parsed = ThinkBlockParser.tryParse(message.content);

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

    return _buildContent(context, message.content);
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
