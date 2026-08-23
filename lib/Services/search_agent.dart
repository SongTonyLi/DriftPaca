import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_tool.dart';
import 'package:llamaseek/Models/research_ledger.dart';
import 'package:llamaseek/Services/web_search_service.dart';
import 'package:llamaseek/Utils/text_similarity.dart';

class SearchAgentRequest {
  final List<OllamaMessage> history;
  final List<OllamaMessage> transcript;
  final bool includeMemory;
  final bool toolsEnabled;

  const SearchAgentRequest({
    required this.history,
    required this.transcript,
    required this.includeMemory,
    required this.toolsEnabled,
  });
}

class SearchAgentSearchRequest {
  final String query;
  final void Function(List<WebSearchResult> urls)? onUrlsKnown;
  final void Function(String url, bool success)? onUrlFetched;
  final bool Function()? isCancelled;

  /// URLs already fetched earlier this run (prior rounds, plus earlier
  /// searches this same round) — purely informational until the search
  /// implementation opts in to honoring it.
  final Set<String> excludeUrls;

  const SearchAgentSearchRequest({
    required this.query,
    this.onUrlsKnown,
    this.onUrlFetched,
    this.isCancelled,
    this.excludeUrls = const {},
  });
}

/// What the completeness gate is asked to judge: the run's objective (the
/// user's question) against the answer the model just drafted for it.
class CoverageRequest {
  final String objective;
  final String draftAnswer;

  const CoverageRequest({
    required this.objective,
    required this.draftAnswer,
  });
}

class SearchAgentListener {
  final void Function(String delta)? onThinking;
  final void Function(String thinking)? onSearchThinking;
  final void Function(String query)? onSearchStart;

  /// Fired once per executed search with its results and the exact
  /// id-to-URL map SearchAgent computed for THIS call (not the cumulative
  /// map across the whole run) — the single place id offsets are computed,
  /// so a caller never needs to re-derive them independently.
  final void Function(List<WebSearchResult> results, Map<int, String> sourceUrls)?
      onSearchComplete;
  final void Function()? onAnswerStart;
  final void Function(String delta)? onContent;
  final void Function()? onResetContent;

  /// Fired once for every planned search that did NOT run — an
  /// intra-turn duplicate, an empty query, a call beyond the search
  /// budget, or a cross-round ledger match — with the same short text
  /// used in that call's tool-role transcript message. One consistent
  /// "a search was skipped" signal regardless of cause.
  final void Function(String query, String reason)? onSearchSkipped;

  /// Fired once per search round after the research ledger updates, with
  /// the run's objective and a snapshot of its sub-goals.
  final void Function(String objective, List<SubGoal> snapshot)?
      onLedgerUpdate;

  /// Fired exactly once, immediately before [SearchAgent.run] returns,
  /// with why the loop stopped.
  final void Function(SearchTerminationReason reason)? onResearchDone;

  const SearchAgentListener({
    this.onThinking,
    this.onSearchThinking,
    this.onSearchStart,
    this.onSearchComplete,
    this.onAnswerStart,
    this.onContent,
    this.onResetContent,
    this.onSearchSkipped,
    this.onLedgerUpdate,
    this.onResearchDone,
  });
}

/// Why a SearchAgent run stopped. Checked in this precedence when several
/// conditions are true simultaneously: [cancelled] (an external stop
/// request) beats every convergence/cap reason; among those,
/// [searchUnavailable] beats [roundCapReached] beats [hardCapReached] beats
/// [unproductiveRounds] beats [converged] (the natural "model just
/// answered" stop with nothing else tripped) — see
/// SearchAgent._terminationReason.
///
/// [searchUnavailable] outranks the caps because it describes the world
/// rather than a policy choice: if the search backend stopped answering,
/// that is why the run ended, whatever counter happens to also be at its
/// limit. Reporting a cap there would tell the user the run was cut short
/// for cost when in fact no research was possible at all.
enum SearchTerminationReason {
  converged,
  unproductiveRounds,
  hardCapReached,
  roundCapReached,

  /// The search backend refused to run queries — rate limited or serving an
  /// anti-bot challenge. No further searches were attempted.
  searchUnavailable,
  cancelled,
}

class SearchAgentOutcome {
  final String content;
  final String thinking;
  final Map<int, String> sourceUrls;
  final int searchCount;
  final bool cancelled;
  final SearchTerminationReason reason;

  const SearchAgentOutcome({
    required this.content,
    required this.thinking,
    required this.sourceUrls,
    required this.searchCount,
    required this.cancelled,
    required this.reason,
  });
}

class SearchAgent {
  // ----------------------------------------------------------------
  // Convergence knobs. Iteration count is not the thing to minimise —
  // more rounds are fine as long as each is productive. These bound cost
  // and wall-clock as the exception path, not the normal way a run ends;
  // normal termination is the model converging (SearchTerminationReason
  // .converged) or the ledger recognising two stalled rounds
  // (.unproductiveRounds) well before any of these fire.
  // ----------------------------------------------------------------

  /// Total unique searches allowed across the whole run.
  static const defaultMaxSearches = 15;

  /// Outer safety rail bounding total model turns regardless of how many
  /// real searches happen — a round that plans zero searches (an
  /// empty-query call, a fully-deduped turn) still doesn't advance
  /// [maxSearches], so without this a model that never emits a useful
  /// query could loop forever. Deliberately generous: normal convergence
  /// (the ledger's stall check, or [maxSearches] itself) is expected to
  /// stop the loop well before this fires.
  static const defaultMaxRounds = 20;

  /// Unique queries accepted per round. Stops a model from spending its
  /// whole search budget as one breadth burst before anything gets read.
  static const defaultRoundBatchCap = 2;

  /// Consecutive unproductive rounds (see run()'s madeProgress /
  /// openedNewSubGoal) tolerated before the loop forces an answer.
  static const defaultStallLimit = 2;

  /// Max searches run against any single research sub-goal (a ledger
  /// entry — see research_ledger.dart) before further attempts on it are
  /// redirected, regardless of how similar the query wording is. A
  /// sub-goal is either answerable with a few tries or it isn't; this is
  /// threshold-insensitive by design, unlike near-duplicate similarity.
  static const defaultPerSubGoalBudget = 3;

  /// Trigram similarity above which a query is refused outright as a
  /// near-duplicate of an existing sub-goal (see _isLedgerBlocked), on top
  /// of the ledger's much lower grouping threshold. Deliberately high —
  /// measured near-duplicate query pairs from a real run topped out
  /// around 0.69, well below this — so legitimate refinements (which are
  /// lexically similar to their parent almost by construction) aren't
  /// mistaken for thrash. The per-sub-goal budget above is what actually
  /// bounds real thrash that stays under this bar.
  static const _ledgerDupeSimilarityThreshold = 0.75;

  /// Rough budget (characters) for RAW tool-message text kept in the
  /// transcript. Once exceeded, the OLDEST rounds with real search results
  /// get rewritten to a short citation-only line — see _compactStaleRounds.
  /// The research ledger (rendered fresh every round), not this raw text,
  /// is what the model actually relies on for "what's already been found"
  /// once a round ages past it.
  static const defaultTranscriptBudgetChars = 60000;

  /// Rounds with real search results kept raw regardless of budget, so a
  /// synthesized answer can always draw on its most recent research
  /// untouched — not just a citation summary of it.
  static const defaultMinRawRounds = 2;

  /// Derives (transcriptBudgetChars, minRawRounds) from the chat's actual
  /// configured context window, so the compaction budget means something
  /// relative to what the model can actually see — [defaultTranscriptBudgetChars]
  /// and [defaultMinRawRounds] are sized for a generous context and say
  /// nothing about a small one (this app's own default is 2048 tokens; see
  /// OllamaChatOptions.contextSize). ~3.5 chars per token (rough English
  /// average) against half the window — the other half is reserved for the
  /// system prompt, chat history, the research ledger, and the model's own
  /// answer. Below a 4096-token window, even [defaultMinRawRounds] (2)
  /// rounds of realistic search results (tens of thousands of chars) dwarf
  /// the whole context, so only the single most recent round is kept as a
  /// hard floor rather than 2 — still enough for a synthesized answer to
  /// cite its freshest evidence. Clamped so a pathologically tiny or huge
  /// configured window still produces a workable budget.
  static ({int transcriptBudgetChars, int minRawRounds}) transcriptLimitsFor(
      int contextSize) {
    const charsPerToken = 3.5;
    const budgetFraction = 0.5;
    final rawBudget = (contextSize * budgetFraction * charsPerToken).round();
    final budget = rawBudget < 4000
        ? 4000
        : (rawBudget > 200000 ? 200000 : rawBudget);
    return (
      transcriptBudgetChars: budget,
      minRawRounds: contextSize <= 4096 ? 1 : defaultMinRawRounds,
    );
  }

  /// Corrective research rounds the completeness gate may force. One
  /// attempt, then whatever the model says next is accepted — same
  /// discipline as the forced-answer guard, since an unbounded gate is an
  /// infinite loop with extra steps.
  static const defaultMaxCoverageChecks = 1;

  final Stream<OllamaMessage> Function(SearchAgentRequest) streamTurn;
  final Future<List<WebSearchResult>> Function(SearchAgentSearchRequest) search;

  /// Judges a drafted answer against the objective and returns the parts it
  /// leaves unaddressed — empty when the answer is complete. Optional: when
  /// null the loop accepts the model's first answer, which is the behavior
  /// every caller had before the gate existed.
  ///
  /// Deliberately separate from [streamTurn]: this is an isolated,
  /// tool-less call that must not pollute the research transcript.
  final Future<List<String>> Function(CoverageRequest)? assessCoverage;
  final int maxCoverageChecks;
  final int maxSearches;
  final int maxRounds;
  final int roundBatchCap;
  final int stallLimit;
  final int perSubGoalBudget;
  final int transcriptBudgetChars;
  final int minRawRounds;

  SearchAgent({
    required this.streamTurn,
    required this.search,
    this.assessCoverage,
    this.maxCoverageChecks = defaultMaxCoverageChecks,
    this.maxSearches = defaultMaxSearches,
    this.maxRounds = defaultMaxRounds,
    this.roundBatchCap = defaultRoundBatchCap,
    this.stallLimit = defaultStallLimit,
    this.perSubGoalBudget = defaultPerSubGoalBudget,
    this.transcriptBudgetChars = defaultTranscriptBudgetChars,
    this.minRawRounds = defaultMinRawRounds,
  });

  Future<SearchAgentOutcome> run({
    required List<OllamaMessage> history,
    required SearchAgentListener listener,
    bool Function()? isCancelled,
  }) async {
    final transcript = <OllamaMessage>[];
    final sourceUrls = <int, String>{};
    final ledger = ResearchLedger(objective: _objectiveFrom(history));
    final roundRecords = <List<_RoundSearchRecord>>[];
    var searchCount = 0;
    var idOffset = 0;
    var allThinking = '';
    var lastContent = '';
    var round = 0;
    var forcedAnswer = false;
    var searchUnavailable = false;
    var coverageChecks = 0;

    while (true) {
      if (isCancelled?.call() == true) {
        return _outcome(lastContent, allThinking, sourceUrls, searchCount, true,
            reason: SearchTerminationReason.cancelled, listener: listener);
      }

      // Computed once per round and used at both checkpoints below so a
      // model that keeps emitting tool_calls after budget/round/stall caps
      // trip can't force another search round just because it ignored
      // toolsEnabled:false on the request.
      // A throttled backend ends research outright rather than counting
      // against the stall limit. Those counters exist to notice a model
      // going in circles; spending two more rounds' worth of requests to
      // "confirm" a block only deepens it, and every one of those rounds
      // would report back as a failed search the model could mistake for
      // evidence that nothing is out there.
      final canSearch = !searchUnavailable &&
          searchCount < maxSearches &&
          round < maxRounds &&
          ledger.roundsSinceProgress < stallLimit &&
          ledger.roundsSinceNewSubGoal < stallLimit;

      final turn = await _streamOneTurn(
        history: history,
        transcript: transcript,
        listener: listener,
        isCancelled: isCancelled,
        toolsEnabled: canSearch,
      );
      allThinking += turn.thinking;
      // Only overwrite when this turn actually said something. lastContent
      // is what a cancelled run falls back on, and a turn that produced
      // nothing — cut short mid-stream, or a bare tool call — has nothing
      // better to offer than the answer already in hand. The preamble path
      // below still clears it explicitly, where discarding really is right.
      if (turn.content.isNotEmpty) lastContent = turn.content;

      if (turn.cancelled) {
        return _outcome(lastContent, allThinking, sourceUrls, searchCount, true,
            reason: SearchTerminationReason.cancelled, listener: listener);
      }

      final hasTools = turn.toolCalls.isNotEmpty && canSearch;
      if (!hasTools) {
        // Dropping `tools` from the request is not enough to make a model
        // stop researching. Handed a tools-disabled request after its budget
        // ran out, gpt-oss:120b keeps emitting a tool call and no prose at
        // all — so the user gets a blank message and loses every fact the
        // run already established. It has to be told, in the transcript,
        // that research is closed. Once only: if it still says nothing we
        // take what we have rather than loop.
        if (turn.content.isEmpty && turn.toolCalls.isNotEmpty && !forcedAnswer) {
          forcedAnswer = true;
          transcript.add(OllamaMessage(
            '',
            role: OllamaMessageRole.assistant,
            thinking: turn.thinking.isEmpty ? null : turn.thinking,
            toolCalls: turn.toolCalls,
          ));
          // Every dangling tool_call needs a tool-role reply or the next
          // request is malformed.
          for (final call in turn.toolCalls) {
            transcript.add(OllamaMessage(
              'Research is closed — no further searches will run. Answer now '
              'using the sources already provided. If some detail could not '
              'be established, say so plainly instead of searching again.',
              role: OllamaMessageRole.tool,
              toolName: call.name,
            ));
          }
          continue;
        }
        // Nothing above forced this answer, so before accepting it, check
        // that it actually answers the question. Three prompt surfaces push
        // the model toward stopping and none push back; the ledger can only
        // see sub-goals the model chose to query, so a part of the question
        // it never asked about can never show up as still-open. This is the
        // only mechanism that can notice.
        if (_shouldRunCoverageGate(
          content: turn.content,
          canSearch: canSearch,
          searchCount: searchCount,
          coverageChecks: coverageChecks,
        )) {
          coverageChecks++;
          final gaps = await _assessGaps(ledger.objective, turn.content);
          if (gaps.isNotEmpty) {
            for (final gap in gaps) {
              ledger.openGap(gap);
            }
            // The rejected answer already streamed to the UI, so clear it
            // there — but keep it in lastContent. If the user cancels during
            // the corrective round, an incomplete draft is still far better
            // than the blank message dd4ed25 exists to prevent; we rejected
            // it hoping to improve on it, not because it was worthless.
            listener.onResetContent?.call();
            transcript.add(OllamaMessage(
              _gapNotice(gaps),
              role: OllamaMessageRole.user,
            ));
            continue;
          }
        }

        if (!turn.answerStarted) {
          listener.onAnswerStart?.call();
          if (turn.content.isNotEmpty) {
            listener.onContent?.call(turn.content);
          }
        }
        return _outcome(
          turn.content, allThinking, sourceUrls, searchCount, false,
          reason: _terminationReason(
              canSearch: canSearch,
              searchUnavailable: searchUnavailable,
              searchCount: searchCount,
              round: round),
          listener: listener,
        );
      }

      listener.onSearchThinking?.call(turn.thinking);
      if (turn.streamedContent || turn.content.isNotEmpty) {
        listener.onResetContent?.call();
        lastContent = '';
      }

      final subGoalsBefore = ledger.subGoals.length;
      final executed = await _executeToolCalls(
        turn.toolCalls,
        remaining: maxSearches - searchCount,
        idOffset: idOffset,
        ledger: ledger,
        roundBatchCap: roundBatchCap,
        excludeUrls: sourceUrls.values.toSet(),
        listener: listener,
        isCancelled: isCancelled,
      );
      if (isCancelled?.call() == true || executed.cancelled) {
        return _outcome(lastContent, allThinking, sourceUrls, searchCount, true,
            reason: SearchTerminationReason.cancelled, listener: listener);
      }
      if (executed.searchUnavailable) searchUnavailable = true;

      _appendLedgerToLastToolMessage(executed.toolMessages, ledger);
      ledger.recordRoundOutcome(
        madeProgress:
            executed.uniqueSearchCount > 0 && executed.anyNonEmptyResults,
        openedNewSubGoal: ledger.subGoals.length > subGoalsBefore,
      );
      listener.onLedgerUpdate
          ?.call(ledger.objective, List<SubGoal>.from(ledger.subGoals));

      transcript.add(OllamaMessage(
        '',
        role: OllamaMessageRole.assistant,
        thinking: turn.thinking.isEmpty ? null : turn.thinking,
        toolCalls: turn.toolCalls,
      ));
      transcript.addAll(executed.toolMessages);
      if (executed.searchRecords.isNotEmpty) {
        final roundNumber = roundRecords.length + 1;
        for (final record in executed.searchRecords) {
          record.round = roundNumber;
        }
        roundRecords.add(executed.searchRecords);
      }
      _compactStaleRounds(roundRecords, transcript);
      sourceUrls.addAll(executed.sourceUrls);
      idOffset = executed.nextOffset;
      searchCount += executed.uniqueSearchCount;
      round++;
    }
  }

  /// Whether to spend a call asking what the drafted answer left out.
  ///
  /// [canSearch] is the load-bearing precondition: if the budget is spent,
  /// the round cap is hit, or the backend is rate-limiting, we could not act
  /// on the answer anyway — and gating a throttled run would contradict the
  /// whole point of ending it. [searchCount] > 0 keeps the gate to genuine
  /// research: an answer produced without searching at all is an ordinary
  /// chat reply, not incomplete research.
  bool _shouldRunCoverageGate({
    required String content,
    required bool canSearch,
    required int searchCount,
    required int coverageChecks,
  }) =>
      assessCoverage != null &&
      content.isNotEmpty &&
      canSearch &&
      searchCount > 0 &&
      coverageChecks < maxCoverageChecks;

  /// Runs the gate, treating any failure as "the answer is complete".
  ///
  /// A gate that throws must never cost the user an answer already in hand:
  /// the downside of wrongly accepting is a partial answer, the downside of
  /// propagating is no answer at all.
  Future<List<String>> _assessGaps(String objective, String draftAnswer) async {
    try {
      final gaps = await assessCoverage!(
          CoverageRequest(objective: objective, draftAnswer: draftAnswer));
      return [
        for (final gap in gaps)
          if (gap.trim().isNotEmpty) gap.trim()
      ];
    } catch (_) {
      return const [];
    }
  }

  static String _gapNotice(List<String> gaps) {
    final buffer = StringBuffer(
        'Your draft answer did not address these parts of my question:\n');
    for (final gap in gaps) {
      buffer.writeln('- $gap');
    }
    return (buffer
          ..writeln()
          ..write('Search for them now, then give the complete answer. Keep '
              'everything you already established — add to it rather than '
              'starting over. If a part genuinely cannot be found, say so '
              'explicitly in your answer.'))
        .toString();
  }

  /// Keeps the transcript's raw tool-message text bounded as a run grows
  /// past a handful of rounds: once total tool-role text exceeds
  /// [transcriptBudgetChars], the OLDEST rounds with real search results
  /// are rewritten in place to a short citation-only line — oldest first,
  /// stopping once back under budget or only [minRawRounds] rounds remain
  /// raw (a hard floor, not a target: if those alone exceed the budget,
  /// they still aren't touched). Mutates the same OllamaMessage objects
  /// already in [transcript] — never adds, removes, or reorders entries
  /// (preserves the pinned assistant+tool-message shape).
  ///
  /// Safe specifically because the research ledger — rendered fresh and
  /// re-appended to the CURRENT round's last tool message every round (see
  /// _appendLedgerToLastToolMessage) — already carries the durable
  /// compressed "what we learned" independently of this raw text. A round
  /// that ages out of the raw window also loses whatever stale ledger copy
  /// had been appended to it while it was current; that's expected, since
  /// the current round always carries its own fresh one.
  void _compactStaleRounds(
    List<List<_RoundSearchRecord>> roundRecords,
    List<OllamaMessage> transcript,
  ) {
    if (roundRecords.length <= minRawRounds) return;
    var total = transcript
        .where((m) => m.role == OllamaMessageRole.tool)
        .fold<int>(0, (sum, m) => sum + m.content.length);
    if (total <= transcriptBudgetChars) return;

    final compactable = roundRecords.length - minRawRounds;
    for (var i = 0; i < compactable && total > transcriptBudgetChars; i++) {
      for (final record in roundRecords[i]) {
        if (record.compacted) continue;
        final before = record.toolMessage.content.length;
        record.toolMessage.content = _compactedLine(record);
        record.compacted = true;
        total -= before - record.toolMessage.content.length;
      }
    }
  }

  static String _compactedLine(_RoundSearchRecord record) {
    final ids = _chainedSourceIds(record.sourceIdStart, record.sourceIdEnd);
    final domains = record.domains.toSet().join(', ');
    // "below", not "above": the ledger always lives on the CURRENT round's
    // last tool message, which — being the most recent round — sorts after
    // every older (and therefore compactable) round in the transcript.
    return '[Round ${record.round}: searched "${record.query}" — sources '
        '$ids ($domains); full text omitted, see the research ledger '
        'below for what has been searched.]';
  }

  static String _chainedSourceIds(int start, int end) {
    final buffer = StringBuffer();
    for (var i = start; i <= end; i++) {
      buffer.write('[$i]');
    }
    return buffer.toString();
  }

  Future<_TurnAccum> _streamOneTurn({
    required List<OllamaMessage> history,
    required List<OllamaMessage> transcript,
    required SearchAgentListener listener,
    required bool Function()? isCancelled,
    required bool toolsEnabled,
  }) async {
    final accum = _TurnAccum();
    final request = SearchAgentRequest(
      history: history,
      transcript: List<OllamaMessage>.from(transcript),
      includeMemory: transcript.isEmpty,
      toolsEnabled: toolsEnabled,
    );

    await for (final chunk in streamTurn(request)) {
      if (isCancelled?.call() == true) {
        accum.cancelled = true;
        return accum;
      }
      _ingestChunk(chunk, accum, listener);
    }
    if (isCancelled?.call() == true) accum.cancelled = true;
    return accum;
  }

  void _ingestChunk(
    OllamaMessage chunk,
    _TurnAccum accum,
    SearchAgentListener listener,
  ) {
    if (chunk.toolCalls != null && chunk.toolCalls!.isNotEmpty) {
      accum.toolCalls.addAll(chunk.toolCalls!);
      if (accum.streamedContent) {
        listener.onResetContent?.call();
        accum.content = '';
        accum.streamedContent = false;
        accum.answerStarted = false;
      }
    }

    final thinking = chunk.thinking;
    if (thinking != null && thinking.isNotEmpty) {
      accum.thinking += thinking;
      listener.onThinking?.call(thinking);
    }

    if (chunk.content.isNotEmpty && accum.toolCalls.isEmpty) {
      if (!accum.answerStarted) {
        listener.onAnswerStart?.call();
        accum.answerStarted = true;
      }
      accum.content += chunk.content;
      listener.onContent?.call(chunk.content);
      accum.streamedContent = true;
    }
  }

  Future<_SearchExec> _executeToolCalls(
    List<OllamaToolCall> toolCalls, {
    required int remaining,
    required int idOffset,
    required ResearchLedger ledger,
    required SearchAgentListener listener,
    required bool Function()? isCancelled,
    int roundBatchCap = 2,
    Set<String> excludeUrls = const {},
  }) async {
    final planned = _planSearches(toolCalls, remaining,
        ledger: ledger, roundBatchCap: roundBatchCap);
    if (planned.isEmpty) return _SearchExec(nextOffset: idOffset);

    final unique = [for (final p in planned) if (p.kind == _PlanKind.unique) p];
    final formattedByKey = <String, String>{};
    // Domain + query + source-id range per executed search, captured now
    // (before formatting discards the result objects) so a round can still
    // be compacted to a citation-only line later — see _compactStaleRounds.
    final compactionMetaByKey = <String, _CompactionMeta>{};
    final urls = <int, String>{};
    // Mutated in place after each search so a later search THIS round also
    // excludes URLs the earlier one just fetched, not just prior rounds'.
    final visited = {...excludeUrls};
    var offset = idOffset;
    var anyNonEmptyResults = false;
    var executedCount = 0;
    var searchUnavailable = false;
    for (final p in unique) {
      if (isCancelled?.call() == true) {
        return _SearchExec(nextOffset: idOffset, cancelled: true);
      }
      listener.onSearchStart?.call(p.query);
      final List<WebSearchResult> results;
      try {
        results = await search(SearchAgentSearchRequest(
          query: p.query,
          isCancelled: isCancelled,
          excludeUrls: Set<String>.unmodifiable(visited),
        ));
      } on WebSearchUnavailableException {
        // Abandon the whole round, not just this call. The remaining
        // queries would hit the same wall, and each extra request into an
        // active block extends it. Whatever ran before this point keeps its
        // results and its place in the transcript.
        searchUnavailable = true;
        break;
      }
      // Counted here rather than as `unique.length`, so a query that never
      // reached a search engine isn't billed against the run's budget as
      // though it had been researched. An empty result set still counts: the
      // request was made and came back with nothing, which is a finding.
      executedCount++;
      if (isCancelled?.call() == true) {
        return _SearchExec(nextOffset: idOffset, cancelled: true);
      }
      // Computed once and reused for both the listener callback and the
      // running id->URL map — a single source of truth for this call's id
      // offsets (see SearchAgentListener.onSearchComplete).
      final callSourceUrls =
          WebSearchService.sourceUrlsFromResults(results, idOffset: offset);
      listener.onSearchComplete?.call(results, callSourceUrls);
      formattedByKey[p.key] = results.isEmpty
          ? 'No results found for "${p.query}". Try a different phrasing, '
              'or check the research ledger below for a still-open '
              'question to search instead.'
          : WebSearchService.formatResultsAsContext(results,
              idOffset: offset, query: p.query);
      urls.addAll(callSourceUrls);
      visited.addAll(results.map((r) => r.url));
      if (results.isNotEmpty) {
        anyNonEmptyResults = true;
        final candidates = <String?>[
          for (final r in results) ...[
            ...?r.chunks,
            r.pageContent,
            r.snippet,
          ],
        ].whereType<String>().toList();
        ledger.markSearched(
          p.subGoal!,
          sourceIdStart: offset + 1,
          sourceIdEnd: offset + results.length,
          excerpt: selectSupportingExcerpt(candidates, p.query),
        );
        compactionMetaByKey[p.key] = _CompactionMeta(
          query: p.query,
          sourceIdStart: offset + 1,
          sourceIdEnd: offset + results.length,
          domains:
              results.map((r) => Uri.tryParse(r.url)?.host ?? r.url).toList(),
        );
      }
      offset += results.length;
    }

    final toolMessages = <OllamaMessage>[];
    final searchRecords = <_RoundSearchRecord>[];
    for (final p in planned) {
      if (p.kind == _PlanKind.unknown) {
        toolMessages.add(OllamaMessage(
          'Unknown tool',
          role: OllamaMessageRole.tool,
          toolName: p.name,
        ));
        continue;
      }
      if (p.kind == _PlanKind.emptyQuery) {
        const reason = 'No query provided; nothing was searched.';
        toolMessages.add(OllamaMessage(reason,
            role: OllamaMessageRole.tool, toolName: 'web_search'));
        listener.onSearchSkipped?.call(p.query, reason);
        continue;
      }
      if (p.kind == _PlanKind.overBudget) {
        const reason = 'Search budget for this question is used up; this '
            'query was not run.';
        toolMessages.add(OllamaMessage(reason,
            role: OllamaMessageRole.tool, toolName: 'web_search'));
        listener.onSearchSkipped?.call(p.query, reason);
        continue;
      }
      if (p.kind == _PlanKind.ledgerDupe) {
        final matched = p.subGoal!;
        final reason = 'You already asked something very close to this — '
            '"${matched.query}". ${matched.status == SubGoalStatus.searched ? 'See the research ledger below for what was found.' : 'That search found nothing new either.'}';
        toolMessages.add(OllamaMessage(reason,
            role: OllamaMessageRole.tool, toolName: 'web_search'));
        listener.onSearchSkipped?.call(p.query, reason);
        continue;
      }
      if (p.kind == _PlanKind.roundBatchCapped) {
        final reason = 'Not run this round — at most $roundBatchCap '
            'searches run per round so each can be read before the next; '
            'ask again next round if still needed.';
        toolMessages.add(OllamaMessage(reason,
            role: OllamaMessageRole.tool, toolName: 'web_search'));
        listener.onSearchSkipped?.call(p.query, reason);
        continue;
      }
      if (p.kind == _PlanKind.dupe) {
        // Same query twice in ONE turn. It shares the executed call's key,
        // so falling through would repeat that call's entire source text a
        // second time — pure context cost for zero new evidence.
        const reason = 'Duplicate of another query in this same turn; see '
            'that result above.';
        toolMessages.add(OllamaMessage(reason,
            role: OllamaMessageRole.tool, toolName: 'web_search'));
        listener.onSearchSkipped?.call(p.query, reason);
        continue;
      }
      final formatted = formattedByKey[p.key];
      if (formatted == null && searchUnavailable) {
        // Either the call that hit the block, or one planned behind it that
        // was never attempted. Both are honestly described the same way:
        // nothing was searched.
        toolMessages.add(OllamaMessage(_searchUnavailableNotice,
            role: OllamaMessageRole.tool, toolName: 'web_search'));
        listener.onSearchSkipped?.call(p.query, _searchUnavailableNotice);
        continue;
      }
      final message = OllamaMessage(
        formatted ?? '',
        role: OllamaMessageRole.tool,
        toolName: 'web_search',
      );
      toolMessages.add(message);
      final meta = compactionMetaByKey[p.key];
      if (meta != null) {
        searchRecords.add(_RoundSearchRecord(
          toolMessage: message,
          query: meta.query,
          sourceIdStart: meta.sourceIdStart,
          sourceIdEnd: meta.sourceIdEnd,
          domains: meta.domains,
        ));
      }
    }

    return _SearchExec(
      toolMessages: toolMessages,
      sourceUrls: urls,
      nextOffset: offset,
      uniqueSearchCount: executedCount,
      anyNonEmptyResults: anyNonEmptyResults,
      searchRecords: searchRecords,
      searchUnavailable: searchUnavailable,
    );
  }

  /// What the model is told when a query could not be run at all.
  ///
  /// This is the whole fix, and it is a context problem rather than a
  /// networking one. A throttled search used to arrive as `No results found
  /// for "X". Try a different phrasing` — which is false twice over: it
  /// reports evidence of absence where there is no evidence at all, and it
  /// explicitly asks for the one behaviour that makes a rate limit worse.
  /// A model handed that either asserts the fact does not exist or spends
  /// the rest of its budget rephrasing into the same wall.
  static const _searchUnavailableNotice =
      'This query was NOT searched — the search engine is rate-limiting this '
      'client, so no request reached the web. This says nothing about '
      'whether an answer exists. Do not rephrase and try again; no further '
      'searches will run this turn. Answer now from the sources already '
      'gathered, and state plainly which parts of the question you could '
      'not verify.';

  List<_Planned> _planSearches(
    List<OllamaToolCall> toolCalls,
    int remaining, {
    required ResearchLedger ledger,
    int roundBatchCap = 2,
  }) {
    final planned = <_Planned>[];
    final seen = <String>{};
    var uniqueCount = 0;
    for (final call in toolCalls) {
      if (call.name != 'web_search') {
        planned.add(_Planned.unknown(call.name));
        continue;
      }
      final query = (call.arguments['query']?.toString() ?? '').trim();
      if (query.isEmpty) {
        planned.add(_Planned.emptyQuery());
        continue;
      }
      final key = _normalizeQuery(query);
      if (seen.contains(key)) {
        planned.add(_Planned.dupe(query, key));
        continue;
      }

      // Ledger identity is checked against a low, permissive threshold
      // (see ResearchLedger.findMatch) purely to find WHICH sub-goal a
      // query belongs to — it never blocks by itself. Whether to actually
      // refuse the search is a separate, much stricter decision.
      final matched = ledger.findMatch(query);
      if (matched != null && _isLedgerBlocked(query, matched)) {
        planned.add(_Planned.ledgerDupe(query, key, matched));
        continue;
      }

      if (uniqueCount >= roundBatchCap) {
        planned.add(_Planned.roundBatchCapped(query, key));
        continue;
      }
      if (uniqueCount >= remaining) {
        planned.add(_Planned.overBudget(query, key));
        continue;
      }
      seen.add(key);
      uniqueCount++;
      // Upserted at plan time (not after the search executes) so a second
      // near-duplicate call later in this same turn also matches it.
      final goal = ledger.upsert(query);
      planned.add(_Planned.unique(query, key, goal));
    }
    return planned;
  }

  /// Whether a query that already matches an existing sub-goal (per
  /// [ResearchLedger.findMatch]) should be refused rather than run again:
  /// a byte-for-byte (normalized) repeat, a near-verbatim rephrasing, or a
  /// sub-goal that's already used up its search budget. Anything else —
  /// including a merely topically-related follow-up — is allowed through,
  /// because a single similarity threshold can't reliably tell a
  /// legitimate refinement from a duplicate (measured near-duplicate and
  /// refinement query pairs score within a few hundredths of each other).
  bool _isLedgerBlocked(String query, SubGoal matched) {
    if (matched.normalizedQuery == _normalizeQuery(query)) return true;
    if (trigramJaccard(query, matched.query) >=
        _ledgerDupeSimilarityThreshold) {
      return true;
    }
    return matched.searchCount >= perSubGoalBudget;
  }

  static String _normalizeQuery(String query) =>
      query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Finds the objective (the last user turn) to seed the research ledger.
  static String _objectiveFrom(List<OllamaMessage> history) {
    for (final m in history.reversed) {
      if (m.role == OllamaMessageRole.user) return m.content;
    }
    return '';
  }

  /// Appends the rendered ledger to the last web_search tool message this
  /// round, so the model sees what's already searched/open in its next
  /// turn — falls back to the last message of any kind if none of this
  /// round's calls were web_search (e.g. an unknown-tool-only turn).
  ///
  /// Invariant: this re-renders and re-appends the ledger onto the CURRENT
  /// round every round; it is never expected to survive once that round
  /// ages out and _compactStaleRounds rewrites its message content.
  static void _appendLedgerToLastToolMessage(
    List<OllamaMessage> toolMessages,
    ResearchLedger ledger,
  ) {
    if (toolMessages.isEmpty) return;
    final ledgerText = ledger.render();
    if (ledgerText.isEmpty) return;
    var targetIndex =
        toolMessages.lastIndexWhere((m) => m.toolName == 'web_search');
    if (targetIndex == -1) targetIndex = toolMessages.length - 1;
    toolMessages[targetIndex].content =
        '${toolMessages[targetIndex].content}\n\n$ledgerText';
  }

  /// Reason for the natural (non-cancelled) stop: whichever cap actually
  /// tripped to make [canSearch] false, or [SearchTerminationReason
  /// .converged] if nothing tripped and the model simply stopped calling
  /// tools on its own. Precedence matches [SearchTerminationReason]'s doc.
  SearchTerminationReason _terminationReason({
    required bool canSearch,
    required bool searchUnavailable,
    required int searchCount,
    required int round,
  }) {
    if (canSearch) return SearchTerminationReason.converged;
    if (searchUnavailable) return SearchTerminationReason.searchUnavailable;
    if (round >= maxRounds) return SearchTerminationReason.roundCapReached;
    if (searchCount >= maxSearches) return SearchTerminationReason.hardCapReached;
    return SearchTerminationReason.unproductiveRounds;
  }

  SearchAgentOutcome _outcome(
    String content,
    String thinking,
    Map<int, String> sourceUrls,
    int searchCount,
    bool cancelled, {
    required SearchTerminationReason reason,
    required SearchAgentListener listener,
  }) {
    listener.onResearchDone?.call(reason);
    return SearchAgentOutcome(
      content: content,
      thinking: thinking,
      sourceUrls: Map<int, String>.from(sourceUrls),
      searchCount: searchCount,
      cancelled: cancelled,
      reason: reason,
    );
  }
}

class _TurnAccum {
  String thinking = '';
  String content = '';
  final toolCalls = <OllamaToolCall>[];
  bool streamedContent = false;
  bool answerStarted = false;
  bool cancelled = false;
}

enum _PlanKind {
  unique,
  dupe,
  unknown,
  emptyQuery,
  overBudget,
  ledgerDupe,
  roundBatchCapped,
}

class _Planned {
  final _PlanKind kind;
  final String query;
  final String key;
  final String name;

  /// The sub-goal this call is searching (kind == unique, freshly
  /// upserted) or was redirected onto (kind == ledgerDupe, an existing
  /// match). Null for every other kind.
  final SubGoal? subGoal;

  const _Planned({
    required this.kind,
    this.query = '',
    this.key = '',
    this.name = 'web_search',
    this.subGoal,
  });

  factory _Planned.unique(String query, String key, SubGoal subGoal) =>
      _Planned(
          kind: _PlanKind.unique, query: query, key: key, subGoal: subGoal);

  factory _Planned.dupe(String query, String key) =>
      _Planned(kind: _PlanKind.dupe, query: query, key: key);

  factory _Planned.unknown(String name) =>
      _Planned(kind: _PlanKind.unknown, name: name);

  factory _Planned.emptyQuery() => const _Planned(kind: _PlanKind.emptyQuery);

  factory _Planned.overBudget(String query, String key) =>
      _Planned(kind: _PlanKind.overBudget, query: query, key: key);

  factory _Planned.ledgerDupe(String query, String key, SubGoal subGoal) =>
      _Planned(
          kind: _PlanKind.ledgerDupe,
          query: query,
          key: key,
          subGoal: subGoal);

  factory _Planned.roundBatchCapped(String query, String key) =>
      _Planned(kind: _PlanKind.roundBatchCapped, query: query, key: key);
}

class _SearchExec {
  final List<OllamaMessage> toolMessages;
  final Map<int, String> sourceUrls;
  final int nextOffset;
  final int uniqueSearchCount;
  final bool cancelled;

  /// Whether at least one search executed this round returned a non-empty
  /// result list — half of run()'s "did this round make progress" check
  /// (the other half is uniqueSearchCount > 0).
  final bool anyNonEmptyResults;

  /// One entry per executed search that returned results — the raw
  /// material for later transcript compaction (see
  /// SearchAgent._compactStaleRounds). Empty when nothing was searched or
  /// every search came back empty.
  final List<_RoundSearchRecord> searchRecords;

  /// Whether a search in this round was refused by the backend (rate limit
  /// or anti-bot challenge) rather than executed. Ends the run — see run()'s
  /// canSearch.
  final bool searchUnavailable;

  _SearchExec({
    this.toolMessages = const [],
    this.sourceUrls = const {},
    required this.nextOffset,
    this.uniqueSearchCount = 0,
    this.cancelled = false,
    this.anyNonEmptyResults = false,
    this.searchRecords = const [],
    this.searchUnavailable = false,
  });
}

/// Domain + query + source-id range for one executed search, captured at
/// fetch time (before results are discarded) so a compacted round can
/// still be described after its raw content is gone.
class _CompactionMeta {
  final String query;
  final int sourceIdStart;
  final int sourceIdEnd;
  final List<String> domains;

  _CompactionMeta({
    required this.query,
    required this.sourceIdStart,
    required this.sourceIdEnd,
    required this.domains,
  });
}

/// Links one executed search back to the exact transcript message holding
/// its raw formatted content, plus enough to rebuild a short citation-only
/// line in its place once that content goes stale — see
/// SearchAgent._compactStaleRounds. [round] is stamped by run() once the
/// record's round number is known; [compacted] guards against rewriting
/// (and re-shrinking the length tally for) the same message twice.
class _RoundSearchRecord {
  final OllamaMessage toolMessage;
  final String query;
  final int sourceIdStart;
  final int sourceIdEnd;
  final List<String> domains;
  int round = 0;
  bool compacted = false;

  _RoundSearchRecord({
    required this.toolMessage,
    required this.query,
    required this.sourceIdStart,
    required this.sourceIdEnd,
    required this.domains,
  });
}
