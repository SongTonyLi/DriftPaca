import 'package:flutter/material.dart';
import 'package:llamaseek/Models/search_event.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shows search details as a bottom sheet with sources and per-source snippets.
class SearchDetailDialog extends StatelessWidget {
  final SearchCardSegment segment;

  const SearchDetailDialog({super.key, required this.segment});

  static void show(BuildContext context, SearchCardSegment segment) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SearchDetailDialog(segment: segment),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.travel_explore, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      segment.query,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
            // Content
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  // Error
                  if (segment.error != null)
                    _ErrorCard(error: segment.error!),
                  // Sources
                  if (segment.urls.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${segment.urls.where((u) => u.state == SearchURLState.success).length} of ${segment.urls.length} sources loaded',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    ...segment.urls.map((url) => _SourceTile(url: url)),
                  ],
                  // Extracted content per source
                  if (segment.extractedContent != null &&
                      segment.extractedContent!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    ..._buildContentCards(theme),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Parse extractedContent into per-source cards.
  /// Format: "domain:\ncontent\n\ndomain:\ncontent"
  List<Widget> _buildContentCards(ThemeData theme) {
    final raw = segment.extractedContent!;
    final parts = raw.split('\n\n');
    final cards = <Widget>[];

    for (final part in parts) {
      final colonIdx = part.indexOf(':\n');
      if (colonIdx == -1) continue;
      final source = part.substring(0, colonIdx).trim();
      final content = part.substring(colonIdx + 2).trim();
      if (content.isEmpty) continue;

      // Truncate very long content
      final display = content.length > 300
          ? '${content.substring(0, 300)}…'
          : content;

      cards.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                source,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                display,
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ));
    }
    return cards;
  }
}

class _ErrorCard extends StatelessWidget {
  final String error;
  const _ErrorCard({required this.error});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(error,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ),
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final SearchURLStatus url;
  const _SourceTile({required this.url});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSuccess = url.state == SearchURLState.success;

    return InkWell(
      onTap: () {
        final uri = Uri.tryParse(url.url);
        if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isSuccess
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                isSuccess ? Icons.check_rounded : Icons.close_rounded,
                size: 14,
                color: isSuccess
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                url.domain,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isSuccess
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.open_in_new_rounded,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}
