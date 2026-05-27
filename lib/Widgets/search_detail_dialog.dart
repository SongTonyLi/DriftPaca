import 'dart:ui';

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

      cards.add(_SourceContentCard(source: source, content: content));
    }
    return cards;
  }
}

/// A source content card that reveals a "Read full" hint behind it when
/// dragged left, and opens [_SourceFullContentDialog] with the complete
/// extracted text on release.
///
/// Mirrors the drag/snap/dialog mechanics from `_ModelTile` in
/// `model_selection_bottom_sheet.dart` so the gesture feels consistent
/// across the app.
class _SourceContentCard extends StatefulWidget {
  final String source;
  final String content;

  const _SourceContentCard({required this.source, required this.content});

  @override
  State<_SourceContentCard> createState() => _SourceContentCardState();
}

class _SourceContentCardState extends State<_SourceContentCard>
    with SingleTickerProviderStateMixin {
  static const _maxSlide = 80.0;
  static const _previewLength = 300;

  late final AnimationController _slideController;
  double _dragOffset = 0;
  double _snapStartOffset = 0;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(_onSnapTick);
  }

  @override
  void dispose() {
    _slideController.removeListener(_onSnapTick);
    _slideController.dispose();
    super.dispose();
  }

  void _onSnapTick() {
    setState(() {
      _dragOffset = lerpDouble(
            _snapStartOffset,
            0,
            Curves.easeOutCubic.transform(_slideController.value),
          ) ??
          0;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    setState(() {
      _dragOffset = (_dragOffset + delta).clamp(-_maxSlide, 0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -400 || _dragOffset < -_maxSlide * 0.4) {
      _showFullContent();
    }
    _snapBack();
  }

  void _snapBack() {
    _snapStartOffset = _dragOffset;
    _slideController.forward(from: 0);
  }

  void _showFullContent() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (dialogContext, animation, _, __) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: const Cubic(0.16, 1.0, 0.3, 1.0),
          reverseCurve: const Cubic(0.4, 0.0, 0.7, 0.2),
        );
        final fade = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
          reverseCurve: const Interval(0.0, 0.7, curve: Curves.easeOut),
        );

        return FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: Tween(begin: 0.94, end: 1.0).animate(curve),
            child: _SourceFullContentDialog(
              source: widget.source,
              content: widget.content,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final progress = (_dragOffset / -_maxSlide).clamp(0.0, 1.0);

    final preview = widget.content.length > _previewLength
        ? '${widget.content.substring(0, _previewLength)}…'
        : widget.content;
    final isTruncated = widget.content.length > _previewLength;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            // Hint revealed behind the card
            Positioned.fill(
              child: Container(
                alignment: Alignment.centerRight,
                decoration: BoxDecoration(
                  color: colorScheme.primary
                      .withValues(alpha: 0.08 + 0.06 * progress),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.only(right: 18),
                child: Opacity(
                  opacity: progress,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.menu_book_outlined,
                        size: 16,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Read full',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Front card that slides
            Transform.translate(
              offset: Offset(_dragOffset, 0),
              child: GestureDetector(
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: isTruncated ? _showFullContent : null,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.source,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (isTruncated)
                                Icon(
                                  Icons.swipe_left_rounded,
                                  size: 14,
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.4),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            preview,
                            style: theme.textTheme.bodySmall?.copyWith(
                              height: 1.5,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Centered modal that displays the full extracted content for one source,
/// styled to match `_ModelInfoCard` from the model selector.
class _SourceFullContentDialog extends StatelessWidget {
  final String source;
  final String content;

  const _SourceFullContentDialog({required this.source, required this.content});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.68,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.90),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.12),
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 50,
                      offset: const Offset(0, 16),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 24, 16, 16),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: colorScheme.onSurface.withValues(alpha: 0.06),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.language_rounded,
                            size: 18,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              source,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: colorScheme.onSurface,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            color: colorScheme.onSurfaceVariant,
                            visualDensity: VisualDensity.compact,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    // Body
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                        child: SelectableText(
                          content,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.6,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
