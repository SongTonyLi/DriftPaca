import 'package:flutter/material.dart';
import 'package:llamaseek/Models/search_event.dart';
import 'package:llamaseek/Widgets/search_detail_dialog.dart';

/// Displays the status of a web search iteration.
/// Shows query, per-URL fetch status, and completion state.
class SearchCard extends StatefulWidget {
  final SearchCardSegment segment;

  const SearchCard({super.key, required this.segment});

  @override
  State<SearchCard> createState() => _SearchCardState();
}

class _SearchCardState extends State<SearchCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = true;
  late final AnimationController _expandController;
  late final Animation<double> _expandAnimation;

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
    _expandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segment = widget.segment;
    final hasError = segment.error != null;

    return Padding(
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
                        '${segment.resultCount} sources',
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
                        children: segment.urls.map((url) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Row(
                              children: [
                                _urlStateIcon(url.state, theme),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    url.domain,
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      color: url.state ==
                                                  SearchURLState.failed ||
                                              url.state ==
                                                  SearchURLState.timedOut
                                          ? theme.colorScheme.onSurfaceVariant
                                              .withValues(alpha: 0.5)
                                          : theme
                                              .colorScheme.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
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

  Widget _urlStateIcon(SearchURLState state, ThemeData theme) {
    switch (state) {
      case SearchURLState.loading:
        return SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: theme.colorScheme.primary,
          ),
        );
      case SearchURLState.success:
        return Icon(Icons.check, size: 12, color: theme.colorScheme.primary);
      case SearchURLState.failed:
        return Icon(Icons.close, size: 12, color: theme.colorScheme.error);
      case SearchURLState.timedOut:
        return Icon(Icons.timer_off_outlined,
            size: 12, color: theme.colorScheme.error);
    }
  }
}
