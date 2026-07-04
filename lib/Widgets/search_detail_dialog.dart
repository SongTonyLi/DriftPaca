import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:llamaseek/Models/search_event.dart';
import 'package:llamaseek/Utils/favicon_cache.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shows search details as a bottom sheet with sources and per-source snippets.
class SearchDetailDialog extends StatelessWidget {
  final SearchCardSegment segment;

  const SearchDetailDialog({super.key, required this.segment});

  static bool _isOpen = false;

  static void show(BuildContext context, SearchCardSegment segment) {
    if (_isOpen) return;
    _isOpen = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SearchDetailDialog(segment: segment),
    ).whenComplete(() => _isOpen = false);
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
            // Content: loaded source cards (with title, favicon, content,
            // tap → open URL, swipe → full content). Failed sources are
            // moved to the bottom as a compact list. The old "X of Y
            // sources loaded" header and per-URL tile list are gone —
            // the cards themselves already convey the loaded state.
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  if (segment.error != null)
                    _ErrorCard(error: segment.error!),
                  ..._buildContentCards(theme),
                  ..._buildFailedSources(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build per-source cards. Prefers the structured `segment.sources`
  /// (carries url + title + content) and falls back to parsing the
  /// legacy `extractedContent` string for messages persisted before the
  /// `sources` field existed.
  List<Widget> _buildContentCards(ThemeData theme) {
    final sources = segment.sources;
    if (sources != null && sources.isNotEmpty) {
      return [
        for (var i = 0; i < sources.length; i++)
          _SourceContentCard(
            domain: sources[i].domain,
            url: sources[i].url,
            title: sources[i].title,
            content: sources[i].content,
            index: i + 1,
          ),
      ];
    }

    // Legacy fallback: "domain:\ncontent\n\ndomain:\ncontent".
    final raw = segment.extractedContent ?? '';
    final parts = raw.split('\n\n');
    final cards = <Widget>[];
    var index = 0;
    for (final part in parts) {
      final colonIdx = part.indexOf(':\n');
      if (colonIdx == -1) continue;
      final domain = part.substring(0, colonIdx).trim();
      final content = part.substring(colonIdx + 2).trim();
      if (content.isEmpty) continue;
      index++;
      cards.add(_SourceContentCard(
        domain: domain,
        url: 'https://$domain',
        title: '',
        content: content,
        index: index,
      ));
    }
    return cards;
  }

  /// Compact list of sources that failed to load (no extracted content).
  /// Rendered at the bottom of the dialog with a muted "Not loaded"
  /// header so it's visually deprioritised but still discoverable.
  List<Widget> _buildFailedSources(ThemeData theme) {
    final failed = segment.urls
        .where((u) => u.state == SearchURLState.failed)
        .toList();
    if (failed.isEmpty) return const [];
    return [
      const SizedBox(height: 18),
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(
          'Not loaded',
          style: theme.textTheme.labelSmall?.copyWith(
            color:
                theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ),
      ...failed.map((u) => _FailedSourceRow(url: u)),
    ];
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
  final String domain;
  final String url;
  final String title;
  final String content;
  final int index;

  const _SourceContentCard({
    required this.domain,
    required this.url,
    required this.title,
    required this.content,
    required this.index,
  });

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

  Future<void> _openUrl() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
              source: widget.domain,
              title: widget.title,
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

    final runes = widget.content.runes;
    final preview = runes.length > _previewLength
        ? '${String.fromCharCodes(runes.take(_previewLength))}…'
        : widget.content;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // Hint revealed behind the card
            Positioned.fill(
              child: Container(
                alignment: Alignment.centerRight,
                decoration: BoxDecoration(
                  color: colorScheme.primary
                      .withValues(alpha: 0.08 + 0.06 * progress),
                  borderRadius: BorderRadius.circular(12),
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
                    onTap: _openUrl,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _FaviconAvatar(domain: widget.domain, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.domain,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: colorScheme.onSurface,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _NumberBubble(number: widget.index),
                            ],
                          ),
                          if (widget.title.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              widget.title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            preview,
                            style: theme.textTheme.bodySmall?.copyWith(
                              height: 1.5,
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.85),
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

/// Small circular favicon used in the source card header. Reads from
/// [FaviconCache] when populated; otherwise fetches once and caches.
class _FaviconAvatar extends StatefulWidget {
  final String domain;
  final double size;

  const _FaviconAvatar({required this.domain, this.size = 18});

  @override
  State<_FaviconAvatar> createState() => _FaviconAvatarState();
}

class _FaviconAvatarState extends State<_FaviconAvatar>
    with SingleTickerProviderStateMixin {
  static const Cubic _popCurve = Cubic(0.34, 1.56, 0.64, 1.0);

  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  Uint8List? _bytes;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _scale = CurvedAnimation(parent: _controller, curve: _popCurve);
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    );

    // Cached bytes → render at full state immediately. Animation is
    // reserved for the "just fetched from network" moment.
    final cache = FaviconCache.instance;
    if (cache.isResolved(widget.domain)) {
      _bytes = cache.bytesFor(widget.domain);
      _resolved = true;
      _controller.value = 1.0;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final bytes = await FaviconCache.instance.fetch(widget.domain);
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _resolved = true;
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = widget.size;
    return SizedBox(
      width: size,
      height: size,
      child: ScaleTransition(
        scale: _scale,
        child: FadeTransition(
          opacity: _fade,
          child: _resolved ? _buildIcon(colorScheme) : null,
        ),
      ),
    );
  }

  Widget _buildIcon(ColorScheme colorScheme) {
    if (_bytes != null) {
      return ClipOval(
        child: Image.memory(
          _bytes!,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _fallback(colorScheme),
        ),
      );
    }
    return _fallback(colorScheme);
  }

  Widget _fallback(ColorScheme colorScheme) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.onSurface.withValues(alpha: 0.10),
      ),
      child: Icon(
        Icons.language_rounded,
        size: widget.size * 0.65,
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
      ),
    );
  }
}

/// Small grey numbered bubble shown at the trailing edge of a source card.
class _NumberBubble extends StatelessWidget {
  final int number;

  const _NumberBubble({required this.number});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withValues(alpha: 0.085),
        borderRadius: BorderRadius.circular(100),
      ),
      alignment: Alignment.center,
      child: Text(
        '$number',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          height: 1.0,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Centered modal that displays the full extracted content for one source,
/// styled to match `_ModelInfoCard` from the model selector.
class _SourceFullContentDialog extends StatelessWidget {
  final String source;
  final String title;
  final String content;

  const _SourceFullContentDialog({
    required this.source,
    required this.title,
    required this.content,
  });

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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _FaviconAvatar(domain: source, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  source,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
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
                          if (title.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: colorScheme.onSurface,
                                letterSpacing: -0.2,
                                height: 1.35,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
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

/// Compact row for a source whose page could not be fetched. Listed at
/// the bottom of the dialog, visually deprioritised but still tappable
/// so the user can open the original URL in a browser if curious.
class _FailedSourceRow extends StatelessWidget {
  final SearchURLStatus url;
  const _FailedSourceRow({required this.url});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final muted = colorScheme.onSurfaceVariant.withValues(alpha: 0.55);

    return InkWell(
      onTap: () {
        final uri = Uri.tryParse(url.url);
        if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Opacity(
              opacity: 0.55,
              child: _FaviconAvatar(domain: url.domain, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                url.domain,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.open_in_new_rounded,
              size: 13,
              color: muted,
            ),
          ],
        ),
      ),
    );
  }
}
