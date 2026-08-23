/// Status of a single URL fetch. `state` is mutable so the view model
/// can flip an entry from `pending` → `success`/`failed` in place as
/// fetches resolve, without rebuilding the whole list. `title` is the
/// page title returned by the search engine — shown in the search card
/// instead of the bare domain. Empty for legacy persisted data.
class SearchURLStatus {
  final String url;
  final String domain;
  final String title;
  SearchURLState state;

  SearchURLStatus({
    required this.url,
    required this.domain,
    this.title = '',
    required this.state,
  });
}

enum SearchURLState { pending, success, failed }

/// Segments for rendering search-augmented messages.
/// Persisted as JSON in the thinking field.
sealed class MessageSegment {}

class ThinkingSegment extends MessageSegment {
  String text;
  ThinkingSegment(this.text);
}

class SearchCardSegment extends MessageSegment {
  String query;
  List<SearchURLStatus> urls;
  int? resultCount;
  String? error;
  bool isComplete;
  String? extractedContent;
  // Structured per-source data (url, domain, title, content) for the
  // detail dialog. Older persisted messages won't have this and the UI
  // falls back to parsing [extractedContent].
  List<SearchSource>? sources;

  /// Ordinal position of this search among all cards shown this run
  /// (1-indexed, real and skipped searches both counted) — rendered as
  /// "Search N" so a long sequence reads as a narrative. Not SearchAgent's
  /// internal batching round (multiple searches can share one of those);
  /// null for messages persisted before this field existed.
  int? round;

  /// Set when this card represents a search the harness declined to run
  /// (a duplicate, an empty query, over budget, ...) instead of one that
  /// actually executed. When set, the UI shows this text in place of the
  /// URL list — a skipped search has none.
  String? skipReason;

  SearchCardSegment({
    required this.query,
    this.urls = const [],
    this.resultCount,
    this.error,
    this.isComplete = false,
    this.extractedContent,
    this.sources,
    this.round,
    this.skipReason,
  });
}

/// One source's full data for the detail dialog: URL, domain (for favicon),
/// page title (from the search result), and extracted text.
class SearchSource {
  final String url;
  final String domain;
  final String title;
  final String content;

  SearchSource({
    required this.url,
    required this.domain,
    required this.title,
    required this.content,
  });
}

/// Snapshot of the research ledger's goal-directed state for one point in a
/// run: the objective and every sub-goal asked so far. Overwritten wholesale
/// each round (mirrors how [SearchCardSegment.urls] is already replaced
/// wholesale rather than diffed) rather than appending a new segment per
/// update, so the bubble shows one panel that grows, not a stack of stale
/// snapshots.
class ResearchLedgerSegment extends MessageSegment {
  String objective;
  List<LedgerEntryView> entries;

  /// [SearchTerminationReason.name] once the run has stopped — null while
  /// still in progress. Kept as a plain string (not the enum itself) so
  /// this model doesn't need to depend on the search service layer.
  String? terminationReason;

  ResearchLedgerSegment({
    required this.objective,
    this.entries = const [],
    this.terminationReason,
  });
}

/// Immutable, UI-facing snapshot of one research sub-goal — decoupled from
/// the harness's mutable `SubGoal` so a later ledger update can't reach back
/// and mutate an already-rendered entry. [searched] mirrors the harness's
/// `SubGoalStatus.searched` naming, deliberately not "established": the
/// harness only knows a search ran and returned something, not that it
/// actually answered the sub-goal.
class LedgerEntryView {
  final String query;
  final bool searched;
  final int? sourceIdStart;
  final int? sourceIdEnd;
  final String? excerpt;

  const LedgerEntryView({
    required this.query,
    required this.searched,
    this.sourceIdStart,
    this.sourceIdEnd,
    this.excerpt,
  });
}

class AnswerSegment extends MessageSegment {}
