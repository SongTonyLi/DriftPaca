import 'package:llamaseek/Utils/text_similarity.dart';

/// A clean restatement of what the user asked, plus the parts of it that
/// need their own lookup — derived once per run before any searching (see
/// SearchAgent.deriveGoal).
///
/// This exists because the raw chat message is a bad research brief in two
/// directions at once. Shown in the UI it reads as what it is — a chat
/// message under a "Research goal" heading. Fed to the model it gives
/// nothing to converge ON, which is how a run wanders through round after
/// round: with no explicit finish line, "have I answered it?" is re-decided
/// from scratch every turn. [subQuestions] become the ledger's checklist,
/// so the finish line is written down and checkable.
class ResearchGoal {
  /// One-line statement of what the run is trying to find out.
  final String statement;

  /// Parts that need separate lookups. Deliberately allowed to be empty:
  /// a single-lookup question decomposed into four sub-questions manufactures
  /// exactly the extra rounds this whole mechanism exists to avoid.
  final List<String> subQuestions;

  const ResearchGoal({required this.statement, this.subQuestions = const []});
}

/// Whether a research sub-goal has been searched at least once. Naming is
/// deliberately modest: the harness only knows a search ran and returned
/// something, not that the sub-goal was actually answered — see
/// [ResearchLedger.recordEvidence].
enum SubGoalStatus { open, searched }

/// A contiguous run of source ids produced by ONE search. A sub-goal
/// accumulates a list of these rather than a single pair, because a
/// second search against the same sub-goal returns ids nowhere near the
/// first one's — see [ResearchLedger.recordEvidence].
class SourceIdRange {
  final int start;
  final int end;

  const SourceIdRange(this.start, this.end);

  int get count => end - start + 1;

  @override
  bool operator ==(Object other) =>
      other is SourceIdRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

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

  /// Every executed search's id range, in the order they were recorded.
  final List<SourceIdRange> ranges = [];
  String? excerpt;

  SubGoal({
    required this.query,
    required this.normalizedQuery,
    this.status = SubGoalStatus.open,
    this.searchCount = 0,
  });

  /// First range only — the evidence this sub-goal has carried since it was
  /// first searched. Kept as a pair (rather than replaced by [ranges]
  /// everywhere) because a great deal of the harness reasons about "the
  /// evidence this sub-goal opened with".
  int? get sourceIdStart => ranges.isEmpty ? null : ranges.first.start;
  int? get sourceIdEnd => ranges.isEmpty ? null : ranges.first.end;
}

/// Tracks what a SearchAgent run has asked, searched, and still has open —
/// the goal-directed state fed back to the model each round so it can see
/// what's already covered instead of re-asking.
class ResearchLedger {
  /// What this run is trying to find out — the derived [ResearchGoal
  /// .statement] when one was produced, otherwise the user's message
  /// verbatim. This is what gets rendered, both to the model and in the UI.
  final String objective;

  /// The user's message verbatim, always. Ground truth for the two
  /// decisions that must not be made against a paraphrase: which instances
  /// the user actually named (see [_requestedInstances]) and whether a
  /// drafted answer covered the question (SearchAgent's completeness gate).
  final String userQuestion;

  final List<SubGoal> subGoals = [];

  /// Consecutive rounds that made no progress (see SearchAgent's
  /// definition of "progress"), used for the stall convergence check.
  int roundsSinceProgress = 0;

  /// Consecutive rounds that covered no new ground — neither opening a new
  /// sub-goal nor searching one that was still open. A second, independent
  /// stall signal: [roundsSinceProgress] is defined per search attempt, so
  /// a model that keeps circling a handful of sub-goals with just enough
  /// lexical variation to dodge the per-sub-goal search budget could
  /// otherwise look "productive" round after round without the research
  /// actually broadening.
  ///
  /// "Or searched one that was still open" is load-bearing once a run
  /// starts with a pre-seeded checklist (see [ResearchGoal.subQuestions]):
  /// every sub-goal already exists on round 1, so a model working steadily
  /// down that list opens nothing new and would otherwise be called stalled
  /// after two rounds — killing the run with most of its own checklist
  /// still unticked.
  int roundsSinceCoverageGrew = 0;

  ResearchLedger({required this.objective, String? userQuestion})
      : userQuestion = userQuestion ?? objective;

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
  /// them covered new ground, so the run read as stalled and stopped
  /// before the last one was ever searched. Keeping them separate also
  /// keeps their evidence legible: [recordEvidence] would happily pile all
  /// four years' sources onto one grouped sub-goal, leaving a single ledger
  /// line that cites everything and distinguishes nothing.
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
  /// actually asked about. Computed once: [userQuestion] is final.
  ///
  /// Deliberately NOT taken from [objective], which may be a model-derived
  /// restatement. The whole safety argument for splitting instances rests
  /// on the years being the user's and not a model's invention (see
  /// [_isDifferentRequestedInstance]); sourcing them from a paraphrase
  /// would quietly hand that guarantee to the same kind of model whose
  /// invented years it exists to reject.
  late final Set<String> _requestedInstances = numericTokens(userQuestion);

  /// Whether [query] pins a different one of the user's requested
  /// instances than [goal] does.
  ///
  /// Gated on the objective on purpose, and this is the whole safety
  /// argument. A model that invents its own year variations is thrashing,
  /// and grouping those is what stops it: in a real gpt-oss:120b trace the
  /// user asked for one city's population and the model re-asked it as
  /// "...2026 estimate", "...2025", "...2026" — three sub-goals' worth of
  /// budget for one question. Because none of those years is in the
  /// objective, they still group, roundsSinceCoverageGrew still fires, and
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

  /// Files one executed search's results against [goal]: marks it searched
  /// and APPENDS the id range, so a sub-goal searched more than once cites
  /// every source it actually gathered.
  ///
  /// Accumulating rather than keeping only the first result set is the fix
  /// for evidence that simply vanished. A query close enough to group onto
  /// an existing sub-goal but not close enough to be refused outright (see
  /// SearchAgent._isLedgerBlocked) runs for real, consumes a block of
  /// source ids, and — under the old first-write-wins rule — was then
  /// dropped on the floor: the ledger showed a gap in its id sequence
  /// (…17–24, then 33–40), the run under-reported how many searches it had
  /// done, and the model was handed sources no ledger line claimed.
  ///
  /// Ranges are appended, never merged, because two searches against one
  /// sub-goal produce ids nowhere near each other — the ids in between
  /// belong to OTHER sub-goals, and widening to a single span would claim
  /// their evidence as this one's.
  ///
  /// The excerpt still keeps the first one that arrived: it is a single
  /// illustrative quote, and there is no reason to prefer a later search's.
  void recordEvidence(
    SubGoal goal, {
    required int sourceIdStart,
    required int sourceIdEnd,
    String? excerpt,
  }) {
    goal.status = SubGoalStatus.searched;
    final range = SourceIdRange(sourceIdStart, sourceIdEnd);
    if (!goal.ranges.contains(range)) goal.ranges.add(range);
    if (goal.excerpt == null && excerpt != null && excerpt.isNotEmpty) {
      goal.excerpt = excerpt;
    }
  }

  /// How many sub-goals have been searched at least once — half of
  /// SearchAgent's "did this round cover new ground" check.
  int get searchedSubGoalCount =>
      subGoals.where((g) => g.status == SubGoalStatus.searched).length;

  /// Updates both stall counters: [roundsSinceProgress] resets on a
  /// productive round and increments otherwise; [roundsSinceCoverageGrew]
  /// resets when this round covered new ground and increments otherwise.
  void recordRoundOutcome({
    required bool madeProgress,
    required bool broadenedCoverage,
  }) {
    roundsSinceProgress = madeProgress ? 0 : roundsSinceProgress + 1;
    roundsSinceCoverageGrew = broadenedCoverage ? 0 : roundsSinceCoverageGrew + 1;
  }

  static String _normalize(String query) =>
      query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static const _groupingThreshold = 0.40;

  /// The stopping rule, stated wherever the ledger is. A research loop that
  /// only ever hears "you may search" re-decides "am I done?" from scratch
  /// every turn and keeps finding reasons not to be; a written finish line
  /// it can check itself against is what actually ends a run early, without
  /// clamping the round cap down to a number that would truncate the
  /// genuinely long questions too.
  ///
  /// Phrased as coverage of the goal, NOT as "tick every box". A literal
  /// quota is the mirror-image failure: a seeded item is worded by one
  /// model and searched by another, so a query that never groups onto it
  /// (see [findMatch]) leaves a `[ ]` nothing can ever tick — and a rule
  /// demanding all-[x] would then drive searching until a cap fires, which
  /// is precisely the wandering this is meant to end.
  ///
  /// Wording also avoids calling a ticked item answered — a search
  /// returning sources is all the harness knows (see [SubGoalStatus]).
  static const stoppingRule =
      'Stop searching and write the answer as soon as your sources cover the '
      'goal above. An [x] item counts as covered, and so does a [ ] item your '
      'searches have already failed to turn anything up for — say plainly in '
      'the answer which parts you could not verify, rather than searching '
      'again. While something is genuinely still missing, search only to '
      'close a specific [ ] item.';

  /// The ledger as the model should see it: the goal, the checklist, and the
  /// stopping rule. Never empty — [render] is the variant that opts out.
  String renderBrief() {
    final buffer = StringBuffer()
      ..writeln('### Research ledger')
      ..writeln('Goal: $objective');

    if (subGoals.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Checklist — [x] means a search returned sources for it, '
            '[ ] means nothing has been searched for it yet:');
      for (final goal in subGoals) {
        buffer.writeln(_checklistLine(goal));
      }
    }

    return (buffer
          ..writeln()
          ..write(stoppingRule))
        .toString()
        .trimRight();
  }

  /// Renders the ledger for the model's context. Empty when no sub-goal
  /// exists at all, so callers can skip appending it entirely.
  String render() => subGoals.isEmpty ? '' : renderBrief();

  static String _checklistLine(SubGoal goal) {
    if (goal.status != SubGoalStatus.searched) return '- [ ] "${goal.query}"';
    final count = goal.ranges.fold<int>(0, (sum, r) => sum + r.count);
    final ids = goal.ranges.map((r) => _chainedIds(r.start, r.end)).join();
    final excerptPart = (goal.excerpt != null && goal.excerpt!.isNotEmpty)
        ? ' Excerpt: "${goal.excerpt}"'
        : '';
    return '- [x] "${goal.query}" -> $count source${count == 1 ? '' : 's'}, '
        'see $ids.$excerptPart';
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
