import 'package:llamaseek/Models/research_ledger.dart';

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

/// One stretch of the model's reasoning.
///
/// At most one segment in a run is live ([isComplete] false): the turn
/// currently streaming. It is mutated in place as deltas arrive and then
/// completed where the turn ends, so the widget rendering it keeps its
/// element — and with it its stopwatch, pulse and collapse animation —
/// instead of being torn down and replaced by a fresh "Thought" row.
/// Every segment decoded from a persisted message is complete.
class ThinkingSegment extends MessageSegment {
  String text;

  /// False only for the one live segment. Rendered as `isStreaming` by the
  /// bubble, which is why a complete segment holds no ticker.
  bool isComplete;

  /// How long this stretch of reasoning took, in seconds — set when a live
  /// segment is completed, and persisted so a reloaded message still reads
  /// "Thought for N seconds". Null for segments that were never live
  /// (the legacy path, and anything saved before this field existed).
  int? elapsedSeconds;

  /// When the live segment opened. Bookkeeping for computing
  /// [elapsedSeconds] at completion time; never persisted, and null on
  /// anything decoded.
  final DateTime? startedAt;

  ThinkingSegment(
    this.text, {
    this.isComplete = true,
    this.elapsedSeconds,
    this.startedAt,
  });
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

  /// True between `onPhase(framingGoal)` and the next phase — the window
  /// where [objective] is still the user's raw question standing in for a
  /// derived goal that has not landed yet. Drives the objective shimmer
  /// and the "Framing the research goal…" next-step line. Never persisted:
  /// a saved message is never mid-derivation.
  bool isDeriving = false;

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

  /// One entry per executed search that returned sources — see
  /// `ResearchLedger.recordEvidence`. A list rather than a single pair
  /// because a sub-goal searched twice cites two id blocks with other
  /// sub-goals' ids in between; collapsing them to one span would claim
  /// evidence this sub-goal never gathered.
  final List<SourceIdRange> ranges;
  final String? excerpt;

  const LedgerEntryView({
    required this.query,
    required this.searched,
    this.ranges = const [],
    this.excerpt,
  });

  /// Total sources across every range — what "N sources" means for this
  /// sub-goal, and what a run's search tally is summed from.
  int get sourceCount =>
      ranges.fold<int>(0, (sum, range) => sum + range.count);
}

/// A question the run put to the user before searching (see
/// `ResearchClarification`), with what they picked. [selected] is null
/// while the card is still waiting for them; an empty list means they
/// chose to continue without answering. Persisted so a saved message still
/// shows what was asked and chosen — the answer is part of how the run
/// understood the question.
class ClarificationSegment extends MessageSegment {
  final String question;
  final List<String> options;
  List<String>? selected;

  ClarificationSegment({
    required this.question,
    required this.options,
    this.selected,
  });

  bool get isAnswered => selected != null;
}

class AnswerSegment extends MessageSegment {}
