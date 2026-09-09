import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_tool.dart';
import 'package:llamaseek/Models/research_ledger.dart';
import 'package:llamaseek/Models/research_phase.dart';
import 'package:llamaseek/Services/web_search_service.dart';
import 'package:llamaseek/Utils/text_similarity.dart';

class SearchAgentRequest {
  final List<OllamaMessage> history;
  final List<OllamaMessage> transcript;
  final bool includeMemory;
  final bool toolsEnabled;

  /// The run's goal, checklist and stopping rule (see
  /// [ResearchLedger.renderBrief]) for the caller to put in front of the
  /// model on EVERY turn — including the first, which has no transcript and
  /// therefore no tool message for the ledger to ride along on.
  ///
  /// That first turn is where a run's shape is decided: a model that plans
  /// its research against a written finish line stops when it reaches one,
  /// where a model handed only a chat message keeps re-deciding whether it
  /// is done and keeps concluding it isn't.
  final String researchBrief;

  const SearchAgentRequest({
    required this.history,
    required this.transcript,
    required this.includeMemory,
    required this.toolsEnabled,
    this.researchBrief = '',
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

  /// Fired whenever the run moves to a new stage — see [ResearchPhase] for
  /// the seam each value marks. Every phase but [ResearchPhase.reading] is
  /// fired from inside this class; that one belongs to the caller's
  /// `search` implementation, which is where a search's URLs become known.
  ///
  /// Repeats are not suppressed: two consecutive turns both report
  /// [ResearchPhase.thinking], because the second one really is a fresh
  /// stretch of thinking and the UI's elapsed-in-phase counter has to
  /// restart with it.
  final void Function(ResearchPhase phase)? onPhase;

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
    this.onPhase,
  });
}

/// Why a SearchAgent run stopped. Checked in this precedence when several
/// conditions are true simultaneously: [cancelled] (an external stop
/// request) beats [stalled] beats every convergence/cap reason; among
/// those, [searchUnavailable] beats [roundCapReached] beats
/// [hardCapReached] beats [unproductiveRounds] beats [converged] (the
/// natural "model just answered" stop with nothing else tripped) — see
/// SearchAgent._terminationReason.
///
/// [searchUnavailable] outranks the caps because it describes the world
/// rather than a policy choice: if the search backend stopped answering,
/// that is why the run ended, whatever counter happens to also be at its
/// limit. Reporting a cap there would tell the user the run was cut short
/// for cost when in fact no research was possible at all.
///
/// [cancelled] and [stalled] are decided in run() straight off the turn
/// rather than by _terminationReason, because neither is a fact about the
/// budgets: both say the turn never finished, so no cap can have been the
/// reason it ended.
enum SearchTerminationReason {
  converged,
  unproductiveRounds,
  hardCapReached,
  roundCapReached,

  /// The search backend refused to run queries — rate limited or serving an
  /// anti-bot challenge. No further searches were attempted.
  searchUnavailable,

  /// The turn delivered nothing for [SearchAgent.turnIdleBudget] — a
  /// provider that opened a stream and then went quiet.
  ///
  /// The run keeps everything it already had and does NOT retry the turn: a
  /// request that has just been silent for minutes will not answer faster on
  /// a second ask, and the wait is the defect. Distinct from [cancelled]
  /// even though both set `SearchAgentOutcome.cancelled` — the user did not
  /// stop this run, the provider did, and the banner has to say so.
  stalled,
  cancelled,
}

class SearchAgentOutcome {
  final String content;
  final String thinking;
  final Map<int, String> sourceUrls;
  final int searchCount;

  /// "This run did not finish normally — do not treat [content] as a
  /// completed answer, and drop a bubble that has nothing in it."
  ///
  /// NOT a record of user intent. It is true both when the user pressed
  /// stop and when the provider went silent
  /// ([SearchTerminationReason.stalled]), because ChatProvider needs the
  /// same cleanup for both. Code that actually cares WHO ended the run must
  /// read [reason].
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
  /// broadenedCoverage) tolerated before the loop forces an answer.
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
  ///
  /// [contextSizeApplies] is false when [contextSize] is never actually
  /// sent to the model — cloud chats, where OllamaService._buildOptions
  /// omits the whole options map (and with it num_ctx) by design. This
  /// function's entire justification is that the budget should mean
  /// something relative to what the model can really see; where the
  /// configured window describes nothing, deriving from it is worse than
  /// not deriving at all. On this app's 2048-token local default it yields
  /// a 4,000-char budget and a 1-round raw floor, stripping every round
  /// but the newest to a text-free citation line and discarding roughly
  /// 200k chars of evidence the real cloud window could have held — which
  /// is exactly the retrieved-but-unmentioned facts users report missing
  /// from long runs. So the derivation is skipped and the constants those
  /// thresholds were sized for are used as-is. This does NOT change local
  /// chats: those still derive from the num_ctx they genuinely send, and
  /// compaction still runs either way — just against
  /// [defaultTranscriptBudgetChars]/[defaultMinRawRounds].
  static ({int transcriptBudgetChars, int minRawRounds}) transcriptLimitsFor(
      int contextSize,
      {bool contextSizeApplies = true}) {
    if (!contextSizeApplies) {
      return (
        transcriptBudgetChars: defaultTranscriptBudgetChars,
        minRawRounds: defaultMinRawRounds,
      );
    }
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

  /// How long a research turn may deliver NOTHING before the run gives up
  /// on it and ends as [SearchTerminationReason.stalled].
  ///
  /// An IDLE deadline, re-armed on every chunk — never a total one. A turn
  /// still emitting reasoning deltas is slow, not stalled, and a reasoning
  /// model working through a long draft can legitimately stream for many
  /// minutes; a total cap would truncate exactly those answers. What is
  /// being bounded is silence.
  ///
  /// This loop is the only layer that can tell the two apart, which is why
  /// the deadline lives here and not on the socket. OpenRouter keeps a slow
  /// request alive with `: OPENROUTER PROCESSING` comment frames — real
  /// bytes arriving on the connection, so a transport-level idle timeout
  /// sees a healthy stream — and [OpenRouterCodec.decodeSseJson] drops them
  /// before they can become chunks, so the loop sees total silence. A
  /// timeout on the HTTP send would fire on the wrong cases and miss this
  /// one.
  ///
  /// Three minutes, sized off the slow-but-alive cases rather than the
  /// healthy ones: the slowest healthy cell in the 2026-09-08 model sweep
  /// took 92s for a whole run, observed time-to-first-token behind those
  /// keep-alives can pass 90s on its own, and a cold local Ollama model
  /// holds the response open while it loads — a minute or more before its
  /// first token, all of it inside this window. The 200ms cancellation poll
  /// in [_streamOneTurn], not a tight deadline, is what keeps an ordinary
  /// slow turn bearable: the user can always stop it.
  static const defaultTurnIdleBudget = Duration(seconds: 180);

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

  /// Turns the user's raw message into a research goal and a checklist,
  /// once, before the first turn. Optional: when null the run uses the
  /// message verbatim as its objective with no pre-seeded sub-goals, which
  /// is the behavior every caller had before this existed.
  ///
  /// Also isolated from [streamTurn] for the same reason [assessCoverage]
  /// is — it must not leave anything in the research transcript.
  ///
  /// A failure here is never fatal: the raw message is a workable objective,
  /// just a worse one, and losing an entire research run because a framing
  /// call timed out would be an absurd trade. See [_deriveGoal].
  final Future<ResearchGoal?> Function(String userQuestion)? deriveGoal;

  /// Puts a derived goal's clarification question to the user and returns
  /// the options they picked — empty when they chose to skip, null when
  /// the run was stopped while waiting. Optional: when null a clarification
  /// the goal asked for is simply not asked, and the run proceeds on the
  /// goal statement alone, exactly as it did before clarifications existed.
  ///
  /// This is the one place the loop waits on a person rather than a model
  /// or a search engine, and it is deliberately before the first turn: a
  /// question asked mid-run would land after searches that may already
  /// have gone the wrong way. Nothing bounds the wait but cancellation —
  /// the user is the one being waited for.
  final Future<List<String>?> Function(ResearchClarification clarification)?
      askClarification;
  final int maxCoverageChecks;
  final int maxSearches;
  final int maxRounds;
  final int roundBatchCap;
  final int stallLimit;
  final int perSubGoalBudget;
  final int transcriptBudgetChars;
  final int minRawRounds;

  /// See [defaultTurnIdleBudget]. Injectable so tests can prove the
  /// deadline exists in milliseconds instead of minutes.
  final Duration turnIdleBudget;

  SearchAgent({
    required this.streamTurn,
    required this.search,
    this.assessCoverage,
    this.deriveGoal,
    this.askClarification,
    this.maxCoverageChecks = defaultMaxCoverageChecks,
    this.maxSearches = defaultMaxSearches,
    this.maxRounds = defaultMaxRounds,
    this.roundBatchCap = defaultRoundBatchCap,
    this.stallLimit = defaultStallLimit,
    this.perSubGoalBudget = defaultPerSubGoalBudget,
    this.transcriptBudgetChars = defaultTranscriptBudgetChars,
    this.minRawRounds = defaultMinRawRounds,
    this.turnIdleBudget = defaultTurnIdleBudget,
  });

  Future<SearchAgentOutcome> run({
    required List<OllamaMessage> history,
    required SearchAgentListener listener,
    bool Function()? isCancelled,
  }) async {
    final transcript = <OllamaMessage>[];
    final sourceUrls = <int, String>{};
    final userQuestion = _objectiveFrom(history);
    // Opened BEFORE the goal call, with the fallback objective (the user's
    // own question) and an empty checklist.
    //
    // Deriving the goal is a whole model request of its own, and nothing
    // reached the UI until it returned — on a reasoning model that is tens
    // of seconds of an empty bubble, because this panel is the first thing
    // a run shows and it was gated on that request. The derived statement
    // and its checklist overwrite this in place the moment they land (the
    // listener updates one panel rather than appending), which is exactly
    // how every later round already refreshes it.
    //
    // Only when there IS a derivation call to wait for: without one the
    // update below already fires immediately, and a second identical
    // publish would say nothing.
    if (deriveGoal != null) {
      listener.onPhase?.call(ResearchPhase.framingGoal);
      listener.onLedgerUpdate?.call(userQuestion, const []);
    }
    final goal = await _deriveGoal(userQuestion);
    // Asked before the ledger exists, because the answer changes what the
    // ledger is judged against: a choice the user made explicitly belongs
    // in the ground truth. Its two halves go to different places, and that
    // is the whole point of splitting the record. The options they TICKED
    // join the instance split, because the user endorsed those strings.
    // The composed question — their picks under the derivation model's own
    // clarification prose — goes only to the completeness gate below.
    final clarified = await _clarify(goal, userQuestion, isCancelled, listener);
    if (clarified == null) {
      return _outcome('', '', sourceUrls, 0, true,
          reason: SearchTerminationReason.cancelled, listener: listener);
    }
    final ledger = ResearchLedger(
      objective: goal.statement,
      // Verbatim, always — see ResearchLedger.userQuestion. Handing it the
      // clarified composition instead made every digit and name in the
      // model's clarification question an instance "the user named", so a
      // model permuting quarter labels out of that question opened a
      // sub-goal and a fresh search budget for each permutation and the
      // stall counter never fired.
      userQuestion: userQuestion,
      clarificationPicks: clarified.picks,
      clarification: clarified.note,
    );
    for (final question in goal.subQuestions) {
      ledger.openGap(question);
    }
    // Published before the first turn, not after the first search round.
    // The goal is known from the outset, so the panel that frames a run
    // should exist from the outset too — created on the first round's
    // update instead, it gets appended below that round's search cards and
    // stays wedged there for the rest of the run, ending up showing the
    // whole run's findings and its "research complete" banner ABOVE
    // searches that had not happened yet when it was placed.
    listener.onLedgerUpdate
        ?.call(ledger.objective, List<SubGoal>.from(ledger.subGoals));
    final roundRecords = <List<_RoundSearchRecord>>[];
    var searchCount = 0;
    var idOffset = 0;
    var allThinking = '';
    var lastContent = '';
    var round = 0;
    var forcedAnswer = false;
    var searchUnavailable = false;
    var coverageChecks = 0;
    _LedgerCarrier? ledgerCarrier;

    while (true) {
      if (isCancelled?.call() == true) {
        return _outcome(lastContent, allThinking, sourceUrls, searchCount, true,
            reason: SearchTerminationReason.cancelled, listener: listener);
      }

      final canSearch = _canSearch(
        ledger: ledger,
        searchUnavailable: searchUnavailable,
        searchCount: searchCount,
        round: round,
      );

      // Announced before the request goes out, not on the first token: the
      // wait for time-to-first-token is exactly the stretch that used to
      // look like nothing was happening.
      listener.onPhase?.call(ResearchPhase.thinking);

      // The brief has to agree with the request it rides on: once the tool
      // is withdrawn it says research is closed, instead of inviting the
      // model to "search only to close a specific [ ] item" on a request
      // that carries no tool — see ResearchLedger.closedRule.
      final turn = await _streamOneTurn(
        history: history,
        transcript: transcript,
        listener: listener,
        isCancelled: isCancelled,
        toolsEnabled: canSearch,
        researchBrief: ledger.renderBrief(closed: !canSearch),
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

      // Checked after cancellation, so a stop that lands while the provider
      // is silent still reports as the user's stop.
      //
      // Ends the run rather than retrying the turn: a provider that has been
      // quiet for minutes will not answer faster on a second ask, and the
      // wait is what makes this a defect. Everything already established
      // survives — searchCount and sourceUrls hold every completed round,
      // and lastContent was updated from turn.content above, so prose
      // streamed before the silence is kept exactly as a cancelled run keeps
      // it.
      //
      // `cancelled: true` is deliberate: ChatProvider reads that flag as
      // "this run did not finish normally, drop an empty bubble", which is
      // precisely what a stalled run needs. The distinct `reason` is what
      // carries the honest explanation to the user.
      if (turn.stalled) {
        return _outcome(lastContent, allThinking, sourceUrls, searchCount, true,
            reason: SearchTerminationReason.stalled, listener: listener);
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
        //
        // Reached only when the model genuinely produced no prose:
        // _ingestChunk no longer manufactures an empty turn out of a
        // withdrawn turn's trailing tool call, so a turn that answered and
        // then asked to search anyway keeps its answer here and leaves this
        // one-shot rescue unspent for the blank turn it was written for.
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
          // Judged against what the user actually typed plus what they
          // clarified, never the derived restatement: "did this answer my
          // question" has exactly one ground truth, and a paraphrase that
          // quietly dropped a clause would make the gate blind to
          // precisely the omission it exists to catch.
          //
          // This string carries the model's own clarification question on
          // purpose — the gate reads prose and needs the refined reading
          // spelled out — which is exactly why it is not what the ledger
          // splits instances on (see ResearchLedger.clarificationPicks).
          final gaps =
              await _assessGaps(clarified.question, turn.content, listener);
          if (gaps.isNotEmpty) {
            for (final gap in gaps) {
              ledger.openGap(gap);
            }
            // The gaps just became [ ] items the model is about to be told
            // to close, so the ledger copy in the transcript and the panel
            // the user is looking at both show them now — not one search
            // round later, and never if the model answers without one.
            ledgerCarrier = _placeLedger(ledgerCarrier, ledger);
            listener.onLedgerUpdate
                ?.call(ledger.objective, List<SubGoal>.from(ledger.subGoals));
            // The rejected answer already streamed to the UI, so clear it
            // there — but keep it in lastContent. If the user cancels during
            // the corrective round, an incomplete draft is still far better
            // than the blank message dd4ed25 exists to prevent; we rejected
            // it hoping to improve on it, not because it was worthless.
            listener.onResetContent?.call();
            // Not cosmetic: _gapNotice tells the model "Keep everything you
            // already established — add to it rather than starting over",
            // and `history` was snapshotted before the run began, so the
            // in-flight bubble isn't there either. Without this line that
            // instruction refers to text present nowhere in the request,
            // and the corrective turn legitimately answers only the gap —
            // which is how the user ends up delivered the delta instead of
            // draft-plus-delta.
            //
            // Content only. No thinking (re-feeding the reasoning that
            // produced the omission argues for repeating it) and no
            // toolCalls — safe because the gate only runs while
            // `canSearch` is true, so a turn carrying tool calls would have
            // `hasTools` true and never reach this branch at all, and
            // nothing dangling can be introduced. (_ingestChunk's "a turn
            // with tool calls has empty content" rule now holds only for
            // tools-enabled turns, so it is no longer what makes this
            // safe.)
            transcript.add(OllamaMessage(
              turn.content,
              role: OllamaMessageRole.assistant,
            ));
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
        // Never return less than we already had. This is the same "take
        // what we have" rule the three cancelled returns apply, and the
        // one the comment on lastContent above already claims to
        // implement. Bounded: lastContent only survives a `continue` via
        // the gate rejection just above (the preamble path clears it), so
        // the fallback can only ever restore a draft the gate itself
        // rejected — which beats the blank bubble dd4ed25 exists to
        // prevent.
        return _outcome(
          turn.content.isNotEmpty ? turn.content : lastContent,
          allThinking,
          sourceUrls,
          searchCount,
          false,
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
      final searchedBefore = ledger.searchedSubGoalCount;
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

      ledger.recordRoundOutcome(
        madeProgress:
            executed.uniqueSearchCount > 0 && executed.anyNonEmptyResults,
        // Ticking a checklist item that was still open counts as new
        // ground, not just opening a brand-new sub-goal. With a pre-seeded
        // checklist every sub-goal exists from round 1, so the old
        // "did the list get longer" test reads a model working steadily
        // down that list as stalled and cuts the run off two rounds in.
        broadenedCoverage: ledger.subGoals.length > subGoalsBefore ||
            ledger.searchedSubGoalCount > searchedBefore,
      );
      searchCount += executed.uniqueSearchCount;
      round++;
      // Counters are final for this round, so this is the same answer the
      // top of the next iteration will compute — the transcript copy of
      // the ledger and the next turn's brief then tell one story.
      final nextCanSearch = _canSearch(
        ledger: ledger,
        searchUnavailable: searchUnavailable,
        searchCount: searchCount,
        round: round,
      );
      ledgerCarrier = _placeLedger(
        ledgerCarrier,
        ledger,
        target: _ledgerTargetIn(executed.toolMessages),
        closed: !nextCanSearch,
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
    }
  }

  /// Whether the next turn may search: the backend is answering and no
  /// budget, round or stall cap has tripped. Computed once per round and
  /// used at every checkpoint, so a model that keeps emitting tool_calls
  /// after a cap trips can't force another search round just because it
  /// ignored toolsEnabled:false on the request.
  ///
  /// A throttled backend ends research outright rather than counting
  /// against the stall limit. Those counters exist to notice a model going
  /// in circles; spending two more rounds' worth of requests to "confirm" a
  /// block only deepens it, and every one of those rounds would report back
  /// as a failed search the model could mistake for evidence that nothing
  /// is out there.
  bool _canSearch({
    required ResearchLedger ledger,
    required bool searchUnavailable,
    required int searchCount,
    required int round,
  }) =>
      !searchUnavailable &&
      searchCount < maxSearches &&
      round < maxRounds &&
      ledger.roundsSinceProgress < stallLimit &&
      ledger.roundsSinceCoverageGrew < stallLimit;

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

  /// Most checklist items a derived goal may open.
  ///
  /// Over-decomposition is this feature's mirror-image regression: the goal
  /// exists to make runs converge, and seeding six sub-questions for a
  /// one-lookup question guarantees the opposite — every one of them is a
  /// [ ] the stopping rule then insists on closing. Capping is cheaper and
  /// more predictable than prompting the behavior away, exactly as with
  /// maxCoverageGaps.
  static const maxGoalSubQuestions = 4;

  /// Asks the goal's clarification question, if it has one and there is
  /// someone to ask. Returns the completeness gate's ground truth (the
  /// user's question with their picks folded in), the one-line note for
  /// the brief, and the picks themselves; null only when the run was
  /// cancelled while waiting.
  ///
  /// The picks travel separately from the composed [question] on purpose:
  /// only they are the user's, and only they may reach the ledger's
  /// instance split — see [ResearchLedger.clarificationPicks].
  ///
  /// Every other failure — no callback, a throw, a skip — lands on the
  /// question as typed with no picks, which is what the run would have
  /// used anyway.
  Future<({String question, String note, List<String> picks})?> _clarify(
    ResearchGoal goal,
    String userQuestion,
    bool Function()? isCancelled,
    SearchAgentListener listener,
  ) async {
    final unclarified =
        (question: userQuestion, note: '', picks: const <String>[]);
    final clarification = goal.clarification;
    if (clarification == null || askClarification == null) return unclarified;
    // Only once there really is a question to put and someone to put it
    // to: reporting the wait for a run that never asks would leave the
    // strip claiming to want an answer nobody was ever shown.
    listener.onPhase?.call(ResearchPhase.awaitingClarification);
    List<String>? selected;
    try {
      selected = await askClarification!(clarification);
    } catch (_) {
      selected = const [];
    }
    if (selected == null || isCancelled?.call() == true) return null;
    final picks = [
      for (final option in selected)
        if (option.trim().isNotEmpty) option.trim()
    ];
    if (picks.isEmpty) return unclarified;
    return (
      question: ResearchClarification.clarifiedQuestion(
          userQuestion, clarification.question, picks),
      note: ResearchClarification.note(clarification.question, picks),
      picks: picks,
    );
  }

  /// Derives the run's goal, falling back to the user's message verbatim.
  ///
  /// Every failure mode lands on that fallback: no callback, a throw, a
  /// null, or a blank statement. The fallback is precisely the behavior
  /// this feature replaces, so degrading to it costs the run nothing but
  /// the improvement.
  Future<ResearchGoal> _deriveGoal(String userQuestion) async {
    final fallback = ResearchGoal(statement: userQuestion);
    if (deriveGoal == null) return fallback;
    try {
      final derived = await deriveGoal!(userQuestion);
      if (derived == null || derived.statement.trim().isEmpty) return fallback;
      return ResearchGoal(
        statement: derived.statement.trim(),
        subQuestions: [
          for (final q in derived.subQuestions)
            if (q.trim().isNotEmpty) q.trim()
        ].take(maxGoalSubQuestions).toList(),
        clarification: derived.clarification,
      );
    } catch (_) {
      return fallback;
    }
  }

  /// Runs the gate, treating any failure as "the answer is complete".
  ///
  /// A gate that throws must never cost the user an answer already in hand:
  /// the downside of wrongly accepting is a partial answer, the downside of
  /// propagating is no answer at all.
  Future<List<String>> _assessGaps(
    String objective,
    String draftAnswer,
    SearchAgentListener listener,
  ) async {
    listener.onPhase?.call(ResearchPhase.checkingCoverage);
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
  /// moved onto the CURRENT round's last tool message every round (see
  /// _placeLedger) — already carries the durable compressed "what we
  /// learned" independently of this raw text. Only the current round ever
  /// carries a copy, so compaction never rewrites a message the ledger is
  /// riding on.
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
    String researchBrief = '',
  }) async {
    final accum = _TurnAccum(toolsEnabled: toolsEnabled);
    final request = SearchAgentRequest(
      history: history,
      transcript: List<OllamaMessage>.from(transcript),
      includeMemory: transcript.isEmpty,
      toolsEnabled: toolsEnabled,
      researchBrief: researchBrief,
    );

    // Opened before either timer is armed: if a streamTurn implementation
    // fails outright rather than returning a stream, that throw must leave
    // no timers behind to fire into a run nobody is waiting on.
    final turnStream = streamTurn(request);

    // Consumed with listen() and a Completer rather than `await for`,
    // because `await for` ties BOTH liveness checks to chunk arrival: the
    // stop button could only be read when a chunk came in, and there was no
    // deadline at all. A provider that opened the stream and went quiet
    // therefore ran neither check, and the run waited forever with the stop
    // button doing nothing (audit finding #1). This is the same shape — and
    // for the same reasons — as ChatProvider._collectWithin, which already
    // bounds the goal and gate calls.
    //
    // A `break` inside `await for` could not have fixed it either: that
    // desugars to awaiting the subscription's cancel(), which on a stalled
    // async* generator blocks on precisely the silence being escaped.
    final finished = Completer<_TurnEnd>();

    // Re-armed on every chunk, so the budget measures SILENCE, not total
    // turn length — see [turnIdleBudget]. Armed before listening as well,
    // so the wait for the first chunk (time-to-first-token, plus whatever
    // the caller's generator does before it yields, e.g. ChatProvider's
    // memory preparation) is inside the window rather than unbounded.
    Timer? idle;
    void armIdle() {
      idle?.cancel();
      idle = Timer(turnIdleBudget, () {
        if (!finished.isCompleted) finished.complete(_TurnEnd.stalled);
      });
    }

    armIdle();
    // Polled rather than checked only on arriving chunks, for the reason
    // _collectWithin documents: a stalled request delivers no chunks by
    // definition, so a per-chunk check cannot fire on exactly the requests
    // the user is most likely to be stopping. Skipped entirely when there
    // is no callback to ask — a poll that can never complete anything is
    // just a timer.
    final cancelPoll = isCancelled == null
        ? null
        : Timer.periodic(const Duration(milliseconds: 200), (_) {
            if (isCancelled() && !finished.isCompleted) {
              finished.complete(_TurnEnd.cancelled);
            }
          });

    final subscription = turnStream.listen(
      (chunk) {
        // The turn is already decided (stalled, or stopped): a chunk that
        // raced the timer must not mutate the accumulator behind the
        // outcome that was already settled on.
        if (finished.isCompleted) return;
        if (isCancelled?.call() == true) {
          finished.complete(_TurnEnd.cancelled);
          // Deliberately NOT ingested. A chunk that arrives after the user
          // pressed stop is discarded rather than appended, so a cancelled
          // turn cannot overwrite the answer already in hand.
          return;
        }
        armIdle();
        try {
          _ingestChunk(chunk, accum, listener);
        } catch (error, stackTrace) {
          // Listener callbacks can throw (ChatProvider's ensureBubble /
          // notifyListeners run in here). Under `await for` such a throw
          // propagated out of run() to the caller's error handling; inside
          // a raw listen it would instead become an unhandled async error
          // and the run would hang. Routing it through the Completer keeps
          // the old contract.
          if (!finished.isCompleted) finished.completeError(error, stackTrace);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        // Stream errors must keep reaching the caller unchanged: this is
        // how an OllamaException from the transport (a 401, a 404, an
        // OpenRouter error frame) becomes ChatProvider's error banner
        // instead of a silently empty answer.
        if (!finished.isCompleted) finished.completeError(error, stackTrace);
      },
      onDone: () {
        if (!finished.isCompleted) finished.complete(_TurnEnd.done);
      },
      cancelOnError: true,
    );

    try {
      final end = await finished.future;
      // Cancellation is re-read on the way out for the same reason the old
      // post-loop check existed: a stop that landed while the last chunks
      // were draining still ends the run as cancelled.
      accum.cancelled =
          end == _TurnEnd.cancelled || isCancelled?.call() == true;
      accum.stalled = end == _TurnEnd.stalled && !accum.cancelled;
      return accum;
    } finally {
      idle?.cancel();
      cancelPoll?.cancel();
      // Not awaited, deliberately — the same rule _collectWithin follows.
      // Cancelling an async* generator only takes effect at its next
      // suspension point, so awaiting this would hang on exactly the stall
      // the deadline exists to escape. The teardown still happens; the run
      // just stops waiting for it.
      subscription.cancel().ignore();
    }
  }

  void _ingestChunk(
    OllamaMessage chunk,
    _TurnAccum accum,
    SearchAgentListener listener,
  ) {
    if (chunk.toolCalls != null && chunk.toolCalls!.isNotEmpty) {
      accum.toolCalls.addAll(chunk.toolCalls!);
      // Discard the prose that preceded the call ONLY while the tool is
      // live. That is the "preamble, then search" case: the search really
      // is about to run, so the prose was throat-clearing. On a
      // tools-withdrawn turn the call cannot run at all — run()'s
      // `hasTools` folds in `canSearch`, and the request carried no tools
      // for the model to call in the first place — and the turn was
      // briefed with ResearchLedger.closedRule ("Write the answer now"),
      // so the prose IS the answer. Deleting it wiped a finished, cited
      // reply off the user's screen and left run() with nothing but a
      // blank message to return: the very failure the forced-answer path
      // below it exists to prevent, reached with the answer in hand.
      //
      // The trade-off, taken deliberately: a model that really does emit a
      // preamble on a closed turn now has that preamble returned as its
      // answer, because run()'s forced-answer rescue keys on
      // `turn.content.isEmpty`. Rescuing those too would mean blanking the
      // bubble before the retry — reintroducing the exact "answer renders,
      // then vanishes" symptom — and, since onContent appends, gluing two
      // answers together in the UI. A thin reply beats a blank one.
      if (accum.toolsEnabled && accum.streamedContent) {
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

    // The same rule, for content arriving AFTER a call: while the tool is
    // live, a turn that has called it is a search turn and its prose is
    // dropped, but a withdrawn turn keeps everything it streams, whichever
    // side of the refused call it arrives on — models emit the two orders
    // interchangeably.
    if (chunk.content.isNotEmpty &&
        (!accum.toolsEnabled || accum.toolCalls.isEmpty)) {
      if (!accum.answerStarted) {
        listener.onAnswerStart?.call();
        listener.onPhase?.call(ResearchPhase.drafting);
        accum.answerStarted = true;
      }
      accum.content += chunk.content;
      listener.onContent?.call(chunk.content);
      accum.streamedContent = true;
    }
  }

  /// The text offered to [selectSupportingExcerpt] for one result, in the
  /// same precedence [WebSearchService.formatResultsAsContext] uses to
  /// decide what the model is actually shown: the chunks when the page was
  /// chunked, else the whole page, else the snippet.
  ///
  /// A page and the chunks it was split into are NEVER both offered. They
  /// used to be, and the ranking could not survive it: [queryCoverage] is
  /// asymmetric containment with only the QUERY's trigram count in the
  /// denominator, so a text can never score below any of its own
  /// substrings. The whole page therefore won every ranking it entered —
  /// and since candidates are pooled across all of a round's results and
  /// ties break toward the earlier candidate, a 200,000-char page
  /// saturating at 1.0 meant the stored evidence degenerated to the
  /// opening characters of the FIRST result whatever it said: on a
  /// reference page, its navigation sidebar.
  ///
  /// Dropping the whole page when chunks exist costs nothing in practice:
  /// production chunks are always `splitText(pageContent, chunkSize: 1500,
  /// overlap: 200)` (web_search_service.dart:177-185), so any phrase up to
  /// the 200-char overlap survives intact inside some chunk.
  @visibleForTesting
  static List<String> excerptCandidates(WebSearchResult r) {
    final chunks = r.chunks;
    final page = r.pageContent;
    return <String>[
      if (chunks != null && chunks.isNotEmpty)
        ...chunks
      else if (page != null && page.isNotEmpty)
        page,
      r.snippet,
    ].where((c) => c.trim().isNotEmpty).toList();
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
      listener.onPhase?.call(ResearchPhase.searching);
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
              'or check the research ledger below for a [ ] item to search '
              'instead.'
          : WebSearchService.formatResultsAsContext(results,
              idOffset: offset, query: p.query);
      urls.addAll(callSourceUrls);
      visited.addAll(results.map((r) => r.url));
      if (results.isNotEmpty) {
        anyNonEmptyResults = true;
        final candidates = [
          for (final r in results) ...excerptCandidates(r),
        ];
        ledger.recordEvidence(
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
      final query = OllamaToolCall.searchQuery(call.arguments);
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
  ///
  /// Two shapes are exempt outright, both of them the completeness gate's
  /// corrective round: a sub-goal the gate opened and nobody has searched,
  /// and a searched sub-goal the gate has REOPENED. Neither holds evidence
  /// the gate accepted, so nothing aimed at them can be a duplicate of
  /// anything.
  bool _isLedgerBlocked(String query, SubGoal matched) {
    // Nothing has been searched for this sub-goal, so there is no duplicate
    // to refuse. This is not hypothetical: the completeness gate opens a
    // sub-goal using the gap's own wording, and the model's natural
    // rephrasing of that gap scores 0.795 against it — over the 0.75
    // threshold — so the harness refused the very search it had just
    // demanded and ended the run as `converged` after one search. It also
    // told the model "That search found nothing new either" about a search
    // that never happened. Requiring a prior search closes both.
    if (matched.searchCount == 0) return false;
    // The same self-contradiction, one case over. A gap the gate filed onto
    // an ALREADY-searched sub-goal (ResearchLedger.openGap) inherits that
    // sub-goal's spent budget and its wording, so every test below would
    // refuse the search _gapNotice has just ordered the model to run — the
    // exact-repeat test included, whenever the gate echoes the query's own
    // words. While a gap is outstanding this sub-goal holds no evidence the
    // gate accepted, so there is nothing here to be a duplicate OF.
    //
    // Bounded, not a hole in the budget: at most maxCoverageGaps gaps from
    // at most maxCoverageChecks gate call per run, at most roundBatchCap
    // searches a round, and ResearchLedger.recordEvidence closes the gap the
    // moment sources land. A corrective search that keeps coming back empty
    // never sets `madeProgress`, so stallLimit ends the run as before.
    if (matched.outstandingGaps.isNotEmpty) return false;
    if (matched.normalizedQuery == _normalizeQuery(query)) return true;
    // Nothing here needs to know about years, versions, quarters or the
    // names of the things asked about. A query naming an instance
    // `matched` does not have never reaches this function, because
    // ResearchLedger.findMatch refuses to call it the same sub-goal in the
    // first place (see ResearchLedger._isDifferentRequestedInstance) — so
    // `matched` names a superset of [query]'s instances, i.e. [query] is
    // at most a narrowing of it, and comparing their string shape means
    // what it says again. Discriminating here instead would have let the
    // search run while still filing its evidence under the first
    // instance's sub-goal, which is where the per-sub-goal budget and the
    // stall counter then truncated a four-part question to three.
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

  /// The message this round's ledger copy rides on: the last web_search
  /// tool message, falling back to the last message of any kind if none of
  /// this round's calls were web_search (e.g. an unknown-tool-only turn).
  /// Null when the round produced no tool message at all.
  static OllamaMessage? _ledgerTargetIn(List<OllamaMessage> toolMessages) {
    if (toolMessages.isEmpty) return null;
    var targetIndex =
        toolMessages.lastIndexWhere((m) => m.toolName == 'web_search');
    if (targetIndex == -1) targetIndex = toolMessages.length - 1;
    return toolMessages[targetIndex];
  }

  /// Moves the transcript's ONE copy of the rendered ledger onto [target]
  /// (or re-renders it in place on the current carrier when [target] is
  /// null), returning the new carrier.
  ///
  /// One copy, not one per round. The ledger used to be appended to every
  /// round's last tool message and left there, so by round three the model
  /// was reading three checklists that disagreed — the oldest still
  /// showing `[ ]` against items later rounds had ticked, each with its
  /// own copy of the stopping rule. A stale `[ ]` is an open invitation to
  /// re-search a closed item, which is the one thing every prompt surface
  /// in this loop is trying to stop. The previous copy is stripped before
  /// the fresh one lands; a carrier that _compactStaleRounds has since
  /// rewritten no longer ends with the suffix and is left alone, since the
  /// rewrite already dropped it.
  static _LedgerCarrier? _placeLedger(
    _LedgerCarrier? current,
    ResearchLedger ledger, {
    OllamaMessage? target,
    bool closed = false,
  }) {
    if (current != null &&
        current.message.content.endsWith(current.suffix)) {
      final content = current.message.content;
      current.message.content =
          content.substring(0, content.length - current.suffix.length);
    }
    final message = target ?? current?.message;
    if (message == null) return null;
    final ledgerText = ledger.render(closed: closed);
    if (ledgerText.isEmpty) return null;
    final suffix = '\n\n$ledgerText';
    message.content = '${message.content}$suffix';
    return _LedgerCarrier(message, suffix);
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
    listener.onPhase?.call(ResearchPhase.done);
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

/// Which transcript message currently carries the rendered ledger, and the
/// exact text appended so it can be stripped again — see
/// SearchAgent._placeLedger.
class _LedgerCarrier {
  final OllamaMessage message;
  final String suffix;

  const _LedgerCarrier(this.message, this.suffix);
}

class _TurnAccum {
  /// Whether THIS turn's request actually carried the search tool. Mirrors
  /// [SearchAgentRequest.toolsEnabled], which ChatProvider turns straight
  /// into `tools:` / `tools: null` on the wire.
  ///
  /// Load-bearing in [SearchAgent._ingestChunk]: a tool call only means
  /// "preamble, then search" while the tool is live. Once it has been
  /// withdrawn, run() refuses the call outright and the turn was briefed
  /// with ResearchLedger.closedRule, so prose streamed alongside a refused
  /// call is the answer rather than throat-clearing ahead of a search.
  ///
  /// The contract that makes this safe is that the flag truthfully
  /// describes what is on the wire: a streamTurn that attached the tool
  /// regardless of [SearchAgentRequest.toolsEnabled] would re-enable the
  /// discard exactly where it is wrong.
  final bool toolsEnabled;

  String thinking = '';
  String content = '';
  final toolCalls = <OllamaToolCall>[];
  bool streamedContent = false;
  bool answerStarted = false;
  bool cancelled = false;

  /// The turn produced nothing for [SearchAgent.turnIdleBudget] and was
  /// abandoned. Never set together with [cancelled] — a user stop that
  /// lands during a stall reads as the stop, since that is the truer
  /// account of why the run ended.
  bool stalled = false;

  _TurnAccum({required this.toolsEnabled});
}

/// How one turn's stream ended. [stalled] is the case that did not exist
/// before: the stream neither closed nor delivered anything.
enum _TurnEnd { done, cancelled, stalled }

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
