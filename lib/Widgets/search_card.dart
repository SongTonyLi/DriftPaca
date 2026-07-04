import 'package:flutter/material.dart';
import 'package:llamaseek/Models/search_event.dart';
import 'package:llamaseek/Widgets/search_detail_dialog.dart';
import 'package:shimmer/shimmer.dart';

/// Displays the status of a web search iteration.
/// Shows query, per-URL fetch status, and completion state.
class SearchCard extends StatefulWidget {
  final SearchCardSegment segment;

  const SearchCard({super.key, required this.segment});

  @override
  State<SearchCard> createState() => _SearchCardState();
}

class _SearchCardState extends State<SearchCard>
    with TickerProviderStateMixin {
  bool _expanded = true;
  late final AnimationController _expandController;
  late final Animation<double> _expandAnimation;

  late final AnimationController _entranceController;
  late final Animation<double> _entranceFade;
  late final Animation<Offset> _entranceSlide;

  // Track previous isComplete state locally because SearchCardSegment is
  // mutable and mutated in-place, so oldWidget.segment === widget.segment.
  bool _prevIsComplete = false;

  @override
  void initState() {
    super.initState();
    _prevIsComplete = widget.segment.isComplete;
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    )..value = 1.0;
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOut,
    );

    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _entranceFade = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _entranceSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    ));
    _entranceController.forward();
  }

  @override
  void didUpdateWidget(SearchCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.segment.isComplete && !_prevIsComplete) {
      _prevIsComplete = true;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _expanded) _toggleExpand();
      });
    }
  }

  void _toggleExpand() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _expandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segment = widget.segment;
    final hasError = segment.error != null;

    return SlideTransition(
      position: _entranceSlide,
      child: FadeTransition(
        opacity: _entranceFade,
        child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: hasError
              ? theme.colorScheme.errorContainer.withValues(alpha: 0.3)
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasError
                ? theme.colorScheme.error.withValues(alpha: 0.3)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            InkWell(
              onTap: () {
                if (widget.segment.isComplete) {
                  SearchDetailDialog.show(context, widget.segment);
                } else if (widget.segment.urls.isNotEmpty) {
                  _toggleExpand();
                }
              },
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    _buildIcon(theme, hasError, segment.isComplete),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _labelText(hasError, segment),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: hasError
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (segment.isComplete && segment.resultCount != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${segment.resultCount} '
                            '${segment.resultCount == 1 ? 'source' : 'sources'}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (segment.urls.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: _expanded ? 0.0 : -0.25,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.keyboard_arrow_down,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // URL list
            SizeTransition(
              sizeFactor: _expandAnimation,
              child: segment.urls.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(
                          left: 36, right: 12, bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final url in segment.urls)
                            _UrlRow(
                              key: ValueKey(url.url),
                              url: url,
                            ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    ),
      ),
    );
  }

  Widget _buildIcon(ThemeData theme, bool hasError, bool isComplete) {
    if (hasError) {
      return Icon(Icons.warning_amber_rounded,
          size: 16, color: theme.colorScheme.error);
    }
    if (isComplete) {
      return Icon(Icons.check_circle_outline,
          size: 16, color: theme.colorScheme.primary);
    }
    return SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: theme.colorScheme.primary,
      ),
    );
  }

  String _labelText(bool hasError, SearchCardSegment segment) {
    if (hasError) return segment.error!;
    if (segment.isComplete) return 'Searched: "${segment.query}"';
    return 'Searching: "${segment.query}"';
  }

}

/// One row of the URL list inside the search card.
///
/// While the row is in [SearchURLState.pending] the domain text is
/// wrapped in a `Shimmer` so it reads as "still loading" — a horizontal
/// highlight sweeps across the text every ~1.4 s. The leading status
/// glyph rides an `AnimatedSwitcher`, so the transition from spinner →
/// check/cross feels deliberate instead of instant.
class _UrlRow extends StatelessWidget {
  final SearchURLStatus url;

  const _UrlRow({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isPending = url.state == SearchURLState.pending;
    final isFailed = url.state == SearchURLState.failed;

    final textColor = isFailed
        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
        : colorScheme.onSurfaceVariant;

    // Prefer the page title from the search engine; fall back to the
    // domain for legacy persisted data (no title) or sites whose search
    // result didn't carry one.
    final display = url.title.trim().isNotEmpty ? url.title : url.domain;

    final titleText = Text(
      display,
      style: theme.textTheme.bodySmall?.copyWith(color: textColor),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          _StatusGlyph(state: url.state),
          const SizedBox(width: 6),
          Expanded(
            child: isPending
                ? Shimmer.fromColors(
                    baseColor: colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.45),
                    highlightColor: colorScheme.onSurface
                        .withValues(alpha: 0.95),
                    period: const Duration(milliseconds: 1400),
                    child: titleText,
                  )
                : titleText,
          ),
        ],
      ),
    );
  }
}

/// 12px status glyph that animates between spinner / check / cross when
/// the URL's [SearchURLState] changes. Uses `AnimatedSwitcher` with a
/// scale + fade transition so the new glyph pops in.
class _StatusGlyph extends StatelessWidget {
  final SearchURLState state;

  const _StatusGlyph({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget glyph;
    switch (state) {
      case SearchURLState.pending:
        glyph = SizedBox(
          key: const ValueKey('pending'),
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation(
              colorScheme.primary.withValues(alpha: 0.75),
            ),
          ),
        );
      case SearchURLState.success:
        glyph = Icon(
          Icons.check_rounded,
          key: const ValueKey('success'),
          size: 13,
          color: colorScheme.primary,
        );
      case SearchURLState.failed:
        glyph = Icon(
          Icons.close_rounded,
          key: const ValueKey('failed'),
          size: 13,
          color: colorScheme.error.withValues(alpha: 0.75),
        );
    }

    return SizedBox(
      width: 14,
      height: 14,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) {
            return ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          child: glyph,
        ),
      ),
    );
  }
}
