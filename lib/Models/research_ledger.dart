import 'package:llamaseek/Utils/text_similarity.dart';

/// Whether a research sub-goal has been searched at least once. Naming is
/// deliberately modest: the harness only knows a search ran and returned
/// something, not that the sub-goal was actually answered — see
/// [ResearchLedger.markSearched].
enum SubGoalStatus { open, searched }

/// One research sub-goal tracked across a SearchAgent run: a query the
/// model asked (or the first phrasing of a cluster of near-duplicates),
/// how many times it's been searched, and — once searched with results —
/// which source ids and excerpt back it up.
class SubGoal {
  final String query;
  final String normalizedQuery;
  SubGoalStatus status;

  /// Number of searches that have been run against this sub-goal (this
  /// query or a query grouped onto it). Backs the per-sub-goal search
  /// budget: SearchAgent stops redirecting new attempts here once this
  /// gets high enough, on the theory that a sub-goal is either answerable
  /// or it isn't — see search_agent.dart's ledger interception.
  int searchCount;
  int? sourceIdStart;
  int? sourceIdEnd;
  String? excerpt;

  SubGoal({
    required this.query,
    required this.normalizedQuery,
    this.status = SubGoalStatus.open,
    this.searchCount = 0,
  });
}

/// Tracks what a SearchAgent run has asked, searched, and still has open —
/// the goal-directed state fed back to the model each round so it can see
/// what's already covered instead of re-asking.
class ResearchLedger {
  final String objective;
  final List<SubGoal> subGoals = [];

  /// Consecutive rounds that made no progress (see SearchAgent's
  /// definition of "progress"), used for the stall convergence check.
  int roundsSinceProgress = 0;

  /// Consecutive rounds where every query mapped onto an already-existing
  /// sub-goal — no new one opened. A second, independent stall signal:
  /// [roundsSinceProgress] is defined per search attempt, so a model that
  /// keeps circling a handful of sub-goals with just enough lexical
  /// variation to dodge the per-sub-goal search budget could otherwise
  /// look "productive" round after round without the research actually
  /// broadening.
  int roundsSinceNewSubGoal = 0;

  ResearchLedger({required this.objective});

  /// Sub-goal identity only — this NEVER decides whether to block a
  /// search; it decides which sub-goal a query belongs to. Checks exact
  /// normalized equality first, then falls back to the closest trigram
  /// match at or above a permissive grouping threshold, so phrasings that
  /// are clearly about the same underlying question (even if not close
  /// enough to call a literal duplicate) land on one sub-goal instead of
  /// spawning a lookalike one. Returns null for a genuinely new question.
  ///
  /// A query naming a different one of the instances the OBJECTIVE asked
  /// about never groups, however similar it looks — see
  /// [_isDifferentRequestedInstance]. Four years the user actually listed
  /// are four questions, and collapsing them onto one sub-goal is what
  /// silently truncated such a question to three parts: they shared a
  /// single per-sub-goal search budget, and after the first round none of
  /// them opened a NEW sub-goal, so the run read as stalled and stopped
  /// before the last one was ever searched. Keeping them separate also
  /// keeps their evidence separate — [markSearched] records only the first
  /// result set per sub-goal, so grouped instances would leave the ledger
  /// citing 2021's sources for all four years.
  SubGoal? findMatch(String query) {
    final normalized = _normalize(query);
    for (final goal in subGoals) {
      if (goal.normalizedQuery == normalized) return goal;
    }
    SubGoal? best;
    var bestScore = 0.0;
    for (final goal in subGoals) {
      if (_isDifferentRequestedInstance(query, goal)) continue;
      final score = trigramJaccard(query, goal.query);
      if (score >= _groupingThreshold && score > bestScore) {
        best = goal;
        bestScore = score;
      }
    }
    return best;
  }

  /// Digit-runs appearing in the user's own question — the instances they
  /// actually asked about. Computed once: [objective] is final.
  late final Set<String> _requestedInstances = numericTokens(objective);

  /// Whether [query] pins a different one of the user's requested
  /// instances than [goal] does.
  ///
  /// Gated on the objective on purpose, and this is the whole safety
  /// argument. A model that invents its own year variations is thrashing,
  /// and grouping those is what stops it: in a real gpt-oss:120b trace the
  /// user asked for one city's population and the model re-asked it as
  /// "...2026 estimate", "...2025", "...2026" — three sub-goals' worth of
  /// budget for one question. Because none of those years is in the
  /// objective, they still group, roundsSinceNewSubGoal still fires, and
  /// that run still ends after three searches exactly as before.
  ///
  /// What changes is only the case where the user themselves named the
  /// instances ("US inflation in 2021, 2022, 2023 and 2024"). There the
  /// years are not the model's invention, and refusing them cost the user
  /// the parts of their own question.
  ///
  /// Deliberately one-directional: a query that DROPS a year the goal has
  /// is a broadening re-ask, not a new instance, and still groups.
  bool _isDifferentRequestedInstance(String query, SubGoal goal) {
    if (_requestedInstances.isEmpty) return false;
    final theirs = numericTokens(goal.query);
    for (final n in numericTokens(query)) {
      if (_requestedInstances.contains(n) && !theirs.contains(n)) return true;
    }
    return false;
  }

  /// Records a search attempt against [query]'s sub-goal: reuses a
  /// matching sub-goal if one exists (bumping its search count), otherwise
  /// creates a new one. Called at plan time — before the search actually
  /// runs — so a second near-duplicate query later in the same turn also
  /// matches it.
  SubGoal upsert(String query) {
    final existing = findMatch(query);
    if (existing != null) {
      existing.searchCount++;
      return existing;
    }
    final goal = SubGoal(query: query, normalizedQuery: _normalize(query))
      ..searchCount = 1;
    subGoals.add(goal);
    return goal;
  }

  /// Records a question that still needs answering but that nobody has
  /// searched for — typically a part of the objective the drafted answer
  /// left unaddressed (see SearchAgent's completeness gate).
  ///
  /// Deliberately not [upsert]: that represents a query actually issued and
  /// increments [SubGoal.searchCount], which would spend the per-sub-goal
  /// search budget on a search that never ran. A gap starts at zero.
  ///
  /// Reuses a matching sub-goal when one exists rather than spawning a
  /// lookalike, and leaves its status and counters alone — a gap naming
  /// something already searched adds nothing.
  SubGoal openGap(String question) {
    final existing = findMatch(question);
    if (existing != null) return existing;
    final goal = SubGoal(query: question, normalizedQuery: _normalize(question));
    subGoals.add(goal);
    return goal;
  }

  /// Marks [goal] searched with supporting evidence. Idempotent: the first
  /// result set that returned something wins — a later redundant search
  /// against the same sub-goal doesn't overwrite the original source range
  /// or excerpt.
  void markSearched(
    SubGoal goal, {
    required int sourceIdStart,
    required int sourceIdEnd,
    String? excerpt,
  }) {
    if (goal.status == SubGoalStatus.searched) return;
    goal.status = SubGoalStatus.searched;
    goal.sourceIdStart = sourceIdStart;
    goal.sourceIdEnd = sourceIdEnd;
    goal.excerpt = excerpt;
  }

  /// Updates both stall counters: [roundsSinceProgress] resets on a
  /// productive round and increments otherwise; [roundsSinceNewSubGoal]
  /// resets when this round opened a genuinely new sub-goal and
  /// increments otherwise.
  void recordRoundOutcome({
    required bool madeProgress,
    required bool openedNewSubGoal,
  }) {
    roundsSinceProgress = madeProgress ? 0 : roundsSinceProgress + 1;
    roundsSinceNewSubGoal = openedNewSubGoal ? 0 : roundsSinceNewSubGoal + 1;
  }

  static String _normalize(String query) =>
      query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static const _groupingThreshold = 0.40;

  /// Renders the ledger for the model's context. Empty when nothing has
  /// been searched yet, so callers can skip appending it entirely.
  String render() {
    if (subGoals.isEmpty) return '';
    final searched = subGoals.where((g) => g.status == SubGoalStatus.searched);
    final open = subGoals.where((g) => g.status == SubGoalStatus.open);

    final buffer = StringBuffer()
      ..writeln('### Research ledger')
      ..writeln('Objective: $objective');

    if (searched.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Searched (evidence gathered — re-search only if these '
            'sources were insufficient):');
      for (final goal in searched) {
        final start = goal.sourceIdStart!;
        final end = goal.sourceIdEnd!;
        final count = end - start + 1;
        final ids = _chainedIds(start, end);
        final excerptPart =
            (goal.excerpt != null && goal.excerpt!.isNotEmpty)
                ? ' Excerpt: "${goal.excerpt}"'
                : '';
        buffer.writeln(
            '- "${goal.query}" -> $count source${count == 1 ? '' : 's'}, '
            'see $ids.$excerptPart');
      }
    }

    if (open.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Still open:');
      for (final goal in open) {
        buffer.writeln('- "${goal.query}"');
      }
    }

    return buffer.toString().trimRight();
  }

  static String _chainedIds(int start, int end) {
    final buffer = StringBuffer();
    for (var i = start; i <= end; i++) {
      buffer.write('[$i]');
    }
    return buffer.toString();
  }
}

/// Picks the candidate excerpt most relevant to [topicText] (typically the
/// search query that produced these candidates), so the ledger can quote
/// something plausibly on-topic rather than an arbitrary chunk. Always
/// returns one of the given strings verbatim — trimmed and, if needed,
/// truncated — never invented text. Returns null if every candidate is
/// empty/blank.
String? selectSupportingExcerpt(
  List<String> candidates,
  String topicText, {
  int maxLength = 220,
}) {
  String? best;
  var bestScore = -1.0;
  for (final candidate in candidates) {
    final trimmed = candidate.trim();
    if (trimmed.isEmpty) continue;
    final score = queryCoverage(topicText, trimmed);
    if (score > bestScore) {
      bestScore = score;
      best = trimmed;
    }
  }
  if (best == null) return null;
  if (best.length <= maxLength) return best;
  return '${best.substring(0, maxLength).trim()}...';
}
