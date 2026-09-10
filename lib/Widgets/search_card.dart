import 'package:flutter/material.dart';
import 'package:llamaseek/Models/search_event.dart';
import 'package:llamaseek/Utils/motion.dart';
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

/// How long the query text takes to clip open on a card that starts live.
const _kQueryReveal = Duration(milliseconds: 320);

/// Per-row delay in the URL stagger, and how long one row takes to arrive.
const _kRowStagger = Duration(milliseconds: 40);
const _kRowReveal = Duration(milliseconds: 260);

/// Rows past this index share the last row's delay, so a 30-source search
/// doesn't take a second and a half to finish landing.
const _kMaxStaggeredRows = 8;

/// One controller drives every row, so the whole stagger is
/// `(cap - 1) * stagger + reveal` long regardless of how many rows landed.
const _kRowsDuration = Duration(
  milliseconds: (_kMaxStaggeredRows - 1) * 40 + 260,
);

/// The completion controller drives both the count-up (its full length) and
/// the progress line's fade-out (the first 300 ms — see [_kProgressFadeEnd]).
const _kCompletion = Duration(milliseconds: 400);
const _kProgressFadeEnd = 300 / 400;

class _SearchCardState extends State<SearchCard>
    with TickerProviderStateMixin {
  bool _expanded = true;
  late final AnimationController _expandController;
  late final Animation<double> _expandAnimation;

  late final AnimationController _entranceController;
  late final Animation<double> _entranceFade;
  late final Animation<Offset> _entranceSlide;
  bool _animationsDisabled = false;

  // Track previous isComplete state locally because SearchCardSegment is
  // mutable and mutated in-place, so oldWidget.segment === widget.segment.
  bool _prevIsComplete = false;

  /// Same reason: `urls` is replaced wholesale on the same segment, so the
  /// only way to see the moment a search's sources become known is to
  /// remember how many there were last build.
  int _prevUrlCount = 0;

  /// A card built from a persisted message (or one already finished when it
  /// first renders) has no progress to show — it starts settled instead of
  /// replaying a run that is already over.
  bool _createdIncomplete = false;

  /// True once this card watched its own search finish. Only then does the
  /// source count count up; a card created complete shows its final number.
  bool _completedLive = false;

  late final AnimationController _queryRevealController;
  late final Animation<double> _queryReveal;

  late final AnimationController _rowsController;

  late final AnimationController _completionController;
  late final Animation<double> _progressFade;
  late final Animation<double> _countUp;

  @override
  void initState() {
    super.initState();
    _prevIsComplete = widget.segment.isComplete;
    _createdIncomplete = !widget.segment.isComplete;
    _prevUrlCount = widget.segment.urls.length;
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

    _queryRevealController = AnimationController(
      duration: _kQueryReveal,
      vsync: this,
      value: _createdIncomplete ? 0.0 : 1.0,
    );
    _queryReveal = CurvedAnimation(
      parent: _queryRevealController,
      curve: Curves.easeOutCubic,
    );

    _rowsController = AnimationController(
      duration: _kRowsDuration,
      vsync: this,
      value: _createdIncomplete ? 0.0 : 1.0,
    );

    _completionController = AnimationController(
      duration: _kCompletion,
      vsync: this,
    );
    _progressFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _completionController,
        curve: const Interval(0.0, _kProgressFadeEnd, curve: Curves.easeOut),
      ),
    );
    _countUp = CurvedAnimation(
      parent: _completionController,
      curve: Curves.easeOut,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animationsDisabled = animationsDisabled(context);
    if (_animationsDisabled) {
      _entranceController.value = 1.0;
      _expandController.value = _expanded ? 1.0 : 0.0;
      _queryRevealController.value = 1.0;
      _rowsController.value = 1.0;
    } else {
      if (_entranceController.value == 0.0 &&
          !_entranceController.isAnimating) {
        _entranceController.forward();
      }
      if (_queryRevealController.value == 0.0 &&
          !_queryRevealController.isAnimating) {
        _queryRevealController.forward();
      }
      // Sources already known at creation still stagger in — the card was
      // built live, they just arrived in the same frame it did.
      if (_prevUrlCount > 0 &&
          _rowsController.value == 0.0 &&
          !_rowsController.isAnimating) {
        _rowsController.forward();
      }
    }
  }

  @override
  void didUpdateWidget(SearchCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final urlCount = widget.segment.urls.length;
    if (urlCount > 0 && _prevUrlCount == 0) {
      if (_animationsDisabled) {
        _rowsController.value = 1.0;
      } else {
        _rowsController.forward(from: 0.0);
      }
    }
    _prevUrlCount = urlCount;

    if (widget.segment.isComplete && !_prevIsComplete) {
      _prevIsComplete = true;
      _completedLive = true;
      // Drives the count-up and retires the progress line. Setting the
      // value outright (rather than animating to it) is what "settles on
      // the first frame" means under reduced motion.
      if (_animationsDisabled) {
        _completionController.value = 1.0;
      } else {
        _completionController.forward(from: 0.0);
      }
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _expanded) _toggleExpand();
      });
    }
  }

  void _toggleExpand() {
    setState(() {
      _expanded = !_expanded;
      if (_animationsDisabled) {
        _expandController.value = _expanded ? 1.0 : 0.0;
      } else if (_expanded) {
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
    _queryRevealController.dispose();
    _rowsController.dispose();
    _completionController.dispose();
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
                // A skipped search has nothing to show — no sources, no
                // extracted content — so it never opens the detail dialog.
                if (widget.segment.skipReason != null) return;
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
                    _buildIcon(theme, hasError, segment.isComplete,
                        segment.skipReason != null),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildLabel(theme, hasError, segment),
                    ),
                    if (segment.isComplete && segment.resultCount != null) ...[
                      const SizedBox(width: 8),
                      _buildSourceCount(theme, segment.resultCount!),
                    ],
                    if (segment.urls.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: _expanded ? 0.0 : -0.25,
                        duration: motionDuration(
                          context,
                          const Duration(milliseconds: 200),
                        ),
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
            // A skipped or failed search has no fetch progress to report.
            if (_createdIncomplete && segment.skipReason == null && !hasError)
              _buildProgressLine(theme, segment),
            // A skipped search has no URLs to show — a compact one-line
            // reason takes the place of the URL list, always visible (no
            // expand/collapse: there's nothing further to disclose).
            if (segment.skipReason != null)
              Padding(
                padding: const EdgeInsets.only(left: 36, right: 12, bottom: 8),
                child: Text(
                  segment.skipReason!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.75),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
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
                            for (var i = 0; i < segment.urls.length; i++)
                              _buildUrlRow(i, segment.urls[i]),
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

  /// The query clips open from the left while the search is live, so the
  /// card reads as something starting rather than something already there.
  /// A card created complete renders it whole.
  Widget _buildLabel(
      ThemeData theme, bool hasError, SearchCardSegment segment) {
    final text = Text(
      _labelText(hasError, segment),
      style: theme.textTheme.bodySmall?.copyWith(
        color: hasError
            ? theme.colorScheme.error
            : theme.colorScheme.onSurfaceVariant,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    // The outer Align absorbs the Expanded's tight width so the inner one
    // is free to shrink-wrap to `widthFactor` of the text.
    return Align(
      alignment: Alignment.centerLeft,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _queryReveal,
          child: text,
          builder: (context, child) => Align(
            key: const ValueKey('search-card-query-clip'),
            alignment: Alignment.centerLeft,
            widthFactor: _queryReveal.value.clamp(0.0, 1.0),
            child: child,
          ),
        ),
      ),
    );
  }

  /// A 2 px line under the header that fills as sources are fetched, then
  /// fades (and collapses) away when the search completes. Only cards that
  /// were live at creation have progress to report.
  Widget _buildProgressLine(ThemeData theme, SearchCardSegment segment) {
    final total = segment.urls.length;
    final fetched = segment.urls
        .where((u) => u.state != SearchURLState.pending)
        .length;
    final fraction = total == 0 ? 0.0 : fetched / total;

    final line = FadeTransition(
      key: const ValueKey('search-card-progress-fade'),
      opacity: _progressFade,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(1),
        child: Container(
          height: 2,
          color: theme.colorScheme.primary.withValues(alpha: 0.12),
          child: AnimatedFractionallySizedBox(
            key: const ValueKey('search-card-progress'),
            alignment: Alignment.centerLeft,
            widthFactor: fraction,
            heightFactor: 1.0,
            duration: motionDuration(
              context,
              const Duration(milliseconds: 260),
            ),
            curve: Curves.easeOutCubic,
            child: DecoratedBox(
              decoration: BoxDecoration(color: theme.colorScheme.primary),
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: AnimatedBuilder(
        animation: _progressFade,
        child: line,
        // Collapsing the height alongside the fade keeps the card from
        // holding 2 px of dead space once the search is over.
        builder: (context, child) =>
            SizedBox(height: 2 * _progressFade.value, child: child),
      ),
    );
  }

  /// "N sources" counts up when this card watched the search finish; a card
  /// created complete (history, or a reload) states its number outright.
  Widget _buildSourceCount(ThemeData theme, int count) {
    Widget label(int value) => Text(
          '$value ${value == 1 ? 'source' : 'sources'}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        );

    if (!_completedLive || _animationsDisabled) return label(count);

    final tween = IntTween(begin: 0, end: count);
    return AnimatedBuilder(
      animation: _countUp,
      builder: (context, _) => label(tween.evaluate(_countUp)),
    );
  }

  /// One URL row, faded and slid into place on its own slice of the
  /// card-level stagger. Rows past [_kMaxStaggeredRows] reuse the last
  /// slice rather than extending the run.
  Widget _buildUrlRow(int index, SearchURLStatus url) {
    final delay = _kRowStagger.inMilliseconds *
        (index < _kMaxStaggeredRows ? index : _kMaxStaggeredRows - 1);
    final total = _kRowsDuration.inMilliseconds;
    final interval = Interval(
      delay / total,
      (delay + _kRowReveal.inMilliseconds) / total,
      curve: Curves.easeOutCubic,
    );

    return SlideTransition(
      key: ValueKey(url.url),
      position: _rowsController.drive(
        Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
            .chain(CurveTween(curve: interval)),
      ),
      child: FadeTransition(
        key: ValueKey('search-card-url-fade-${url.url}'),
        opacity: _rowsController.drive(CurveTween(curve: interval)),
        child: _UrlRow(url: url),
      ),
    );
  }

  Widget _buildIcon(
      ThemeData theme, bool hasError, bool isComplete, bool isSkipped) {
    final Widget icon;
    if (isSkipped) {
      icon = Icon(Icons.skip_next_rounded,
          key: const ValueKey('skipped'),
          size: 16,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6));
    } else if (hasError) {
      icon = Icon(Icons.warning_amber_rounded,
          key: const ValueKey('error'),
          size: 16,
          color: theme.colorScheme.error);
    } else if (isComplete) {
      icon = Icon(Icons.check_circle_outline,
          key: const ValueKey('complete'),
          size: 16,
          color: theme.colorScheme.primary);
    } else if (_animationsDisabled) {
      icon = Icon(
        Icons.hourglass_top_rounded,
        key: const ValueKey('running'),
        size: 16,
        color: theme.colorScheme.primary,
      );
    } else {
      icon = SizedBox(
        key: const ValueKey('running'),
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: theme.colorScheme.primary,
        ),
      );
    }

    return SizedBox(
      width: 16,
      height: 16,
      child: Center(
        child: AnimatedSwitcher(
          duration: motionDuration(
            context,
            const Duration(milliseconds: 280),
          ),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: icon,
        ),
      ),
    );
  }

  /// [SearchCardSegment.round] (when present — null for messages persisted
  /// before the field existed) renders as a leading "Search N ·" ordinal so
  /// a sequence of many cards, real and skipped alike, reads as one
  /// narrative instead of N identical-looking entries.
  String _labelText(bool hasError, SearchCardSegment segment) {
    final prefix =
        segment.round != null ? 'Search ${segment.round} · ' : '';
    if (segment.skipReason != null) {
      return segment.query.isEmpty
          ? '${prefix}Skipped'
          : '${prefix}Skipped: "${segment.query}"';
    }
    if (hasError) return '$prefix${segment.error!}';
    if (segment.isComplete) return '${prefix}Searched: "${segment.query}"';
    return '${prefix}Searching: "${segment.query}"';
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

  const _UrlRow({required this.url});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final disabled = animationsDisabled(context);
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
            child: isPending && !disabled
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
    final disabled = animationsDisabled(context);

    Widget glyph;
    switch (state) {
      case SearchURLState.pending:
        glyph = disabled
            ? Icon(
                Icons.hourglass_top_rounded,
                key: const ValueKey('pending'),
                size: 13,
                color: colorScheme.primary.withValues(alpha: 0.75),
              )
            : SizedBox(
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
          duration: motionDuration(
            context,
            const Duration(milliseconds: 280),
          ),
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
