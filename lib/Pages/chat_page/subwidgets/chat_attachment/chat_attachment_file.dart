import 'package:flutter/material.dart';
import 'package:llamaseek/Models/chat_attachment.dart';

class ChatAttachmentFile extends StatelessWidget {
  static const double previewHeight = 72;

  final ChatAttachment attachment;
  final ValueChanged<ChatAttachment> onRemove;

  const ChatAttachmentFile({
    super.key,
    required this.attachment,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 168, maxWidth: 220),
      child: Stack(
        children: [
          Container(
            height: previewHeight,
            padding: const EdgeInsets.fromLTRB(12, 10, 36, 10),
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.16),
              ),
            ),
            child: Row(
              children: [
                Icon(iconFor(attachment), size: 28, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attachment.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitleFor(attachment),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: InkWell(
              onTap: () => onRemove(attachment),
              customBorder: const CircleBorder(),
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: Icon(Icons.close, size: 18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static IconData iconFor(ChatAttachment attachment) {
    switch (attachment.kind) {
      case ChatAttachmentKind.pdf:
        return Icons.picture_as_pdf_outlined;
      case ChatAttachmentKind.image:
        return Icons.image_outlined;
      case ChatAttachmentKind.document:
        final name = attachment.fileName.toLowerCase();
        if (name.endsWith('.xlsx')) return Icons.table_chart_outlined;
        if (name.endsWith('.pptx')) return Icons.slideshow_outlined;
        return Icons.description_outlined;
    }
  }

  static String subtitleFor(ChatAttachment attachment) {
    switch (attachment.kind) {
      case ChatAttachmentKind.pdf:
        final pages = attachment.pageCount;
        if (pages != null && pages > 0) {
          return pages == 1 ? 'PDF · 1 page' : 'PDF · $pages pages';
        }
        return attachment.hasExtractedText ? 'PDF · text extracted' : 'PDF';
      case ChatAttachmentKind.image:
        return 'Image';
      case ChatAttachmentKind.document:
        return attachment.hasExtractedText ? 'Document · text extracted' : 'Document';
    }
  }
}

class ChatBubbleFileChip extends StatelessWidget {
  final ChatAttachment attachment;

  const ChatBubbleFileChip({super.key, required this.attachment});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ChatAttachmentFile.iconFor(attachment),
            size: 20,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              attachment.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }
}
