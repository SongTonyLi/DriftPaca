import 'package:flutter/material.dart';
import 'package:llamaseek/Models/search_event.dart';

/// Shows search details: query, sources with status, and extracted content.
class SearchDetailDialog extends StatelessWidget {
  final SearchCardSegment segment;

  const SearchDetailDialog({super.key, required this.segment});

  static void show(BuildContext context, SearchCardSegment segment) {
    showDialog(
      context: context,
      builder: (context) => SearchDetailDialog(segment: segment),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(
        'Search: "${segment.query}"',
        style: theme.textTheme.titleMedium,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sources section
              if (segment.urls.isNotEmpty) ...[
                Text('Sources',
                    style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary)),
                const SizedBox(height: 8),
                ...segment.urls.map((url) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(
                            url.state == SearchURLState.success
                                ? Icons.check_circle
                                : Icons.cancel,
                            size: 14,
                            color: url.state == SearchURLState.success
                                ? theme.colorScheme.primary
                                : theme.colorScheme.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              url.domain,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: url.state == SearchURLState.success
                                    ? null
                                    : theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.5),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 16),
              ],
              // Error section
              if (segment.error != null) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer
                        .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(segment.error!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error)),
                ),
                const SizedBox(height: 16),
              ],
              // Key content section
              if (segment.extractedContent != null &&
                  segment.extractedContent!.isNotEmpty) ...[
                Text('Key Content',
                    style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    segment.extractedContent!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      height: 1.5,
                    ),
                  ),
                ),
              ],
              // No content message
              if ((segment.extractedContent == null ||
                      segment.extractedContent!.isEmpty) &&
                  segment.error == null)
                Text('No content extracted.',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
