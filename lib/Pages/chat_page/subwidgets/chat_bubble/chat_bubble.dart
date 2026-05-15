import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_markdown_latex/flutter_markdown_latex.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:reins/Extensions/markdown_stylesheet_extension.dart';
import 'package:reins/Models/ollama_message.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'chat_bubble_actions.dart';
import 'chat_bubble_image.dart';
import 'chat_bubble_menu.dart';
import 'chat_bubble_think_block.dart' show ThinkBlockParser, ThinkBlockWidget;

class ChatBubble extends StatelessWidget {
  final OllamaMessage message;

  const ChatBubble({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final actions = ChatBubbleActions(message);

    return ChatBubbleMenu(
      menuChildren: [
        MenuItemButton(
          onPressed: actions.handleCopy,
          leadingIcon: Icon(Icons.copy_outlined),
          child: const Text('Copy'),
        ),
        MenuItemButton(
          onPressed: () => actions.handleSelectText(context),
          leadingIcon: Icon(Icons.select_all_outlined),
          child: const Text('Select Text'),
        ),
        MenuItemButton(
          onPressed: () => actions.handleRegenerate(context),
          leadingIcon: Icon(Icons.refresh_outlined),
          child: const Text('Regenerate'),
        ),
        Divider(),
        MenuItemButton(
          onPressed: () => actions.handleEdit(context),
          closeOnActivate: false,
          leadingIcon: Icon(Icons.edit_outlined),
          child: const Text('Edit'),
        ),
        MenuItemButton(
          onPressed: () => actions.handleDelete(context),
          leadingIcon: Icon(Icons.delete_outline),
          child: const Text('Delete'),
        ),
      ],
      child: _ChatBubbleBody(message: message),
    );
  }
}

class _ChatBubbleBody extends StatelessWidget {
  final OllamaMessage message;

  const _ChatBubbleBody({required this.message});

  bool get isSentFromUser => message.role == OllamaMessageRole.user;

  CrossAxisAlignment get bubbleAlignment =>
      isSentFromUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: isSentFromUser ? 60.0 : 16.0,
        right: 16.0,
        top: 4.0,
        bottom: 4.0,
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
            _AssistantBubble(message: message, buildMarkdown: _buildMarkdown),
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

    return CustomPaint(
      painter: _BubbleTailPainter(color: color),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18.0),
            topRight: Radius.circular(18.0),
            bottomLeft: Radius.circular(18.0),
            bottomRight: Radius.circular(4.0),
          ),
        ),
        child: buildMarkdown(context, message.content),
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  final OllamaMessage message;
  final Widget Function(BuildContext, String) buildMarkdown;

  const _AssistantBubble({required this.message, required this.buildMarkdown});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 6.0),
      child: _buildMessageContent(context),
    );
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
          if (message.content.isNotEmpty)
            buildMarkdown(context, message.content),
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
          if (parsed.responseContent.isNotEmpty)
            buildMarkdown(context, parsed.responseContent),
        ],
      );
    }

    return buildMarkdown(context, message.content);
  }
}

class _BubbleTailPainter extends CustomPainter {
  final Color color;

  _BubbleTailPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();

    // Small tail at bottom-right
    path.moveTo(size.width - 4, size.height - 2);
    path.lineTo(size.width + 6, size.height + 4);
    path.lineTo(size.width - 10, size.height - 2);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
