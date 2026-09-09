/// Guard: a gap the completeness gate files is always visible, is never
/// refused by the ledger's duplicate rules, and closing it counts as
/// coverage growing.
///
/// `SearchAgent.run` files every gap the gate returns with
/// `ResearchLedger.openGap`, which calls `findMatch` first — so a gap worded
/// at or above `ResearchLedger._groupingThreshold` (0.40) trigram-similar to
/// a sub-goal that has ALREADY been searched lands on that sub-goal instead
/// of opening its own. `openGap` used to return that sub-goal untouched, and
/// three separate mechanisms then read stale state from the one fact nobody
/// had written down:
///
///   * the checklist kept rendering `- [x] "<the old query>"`, so the brief
///     the corrective turn reads said "An [x] item counts as covered" about
///     ground the gate had just rejected, while `_gapNotice` in the same
///     request said "Search for them now" about wording the brief never
///     showed;
///   * `_isLedgerBlocked` saw a sub-goal at its per-sub-goal budget and
///     refused the corrective search — the `matched.searchCount == 0` guard
///     added, per its own comment, precisely so "the harness refused the very
///     search it had just demanded" could not recur covers only gaps landing
///     on an UNSEARCHED sub-goal;
///   * `searchedSubGoalCount` went on counting the sub-goal as covered
///     ground, so even when the corrective search DID run it registered no
///     coverage growth and the round the harness itself demanded advanced the
///     stall counter — ending the run as `unproductiveRounds`, the model
///     blamed for a round the harness emptied.
///
/// What this file now pins: `openGap` reuses the sub-goal (still no
/// lookalike, still no billed search) and files the gap on it as an
/// outstanding gap; the brief unticks that item, quotes the gap verbatim and
/// keeps citing the sources the earlier search gathered;
/// `_isLedgerBlocked`'s `outstandingGaps` bypass lets the demanded search
/// run whatever the budget says; and `recordEvidence` closes the gap, so the
/// corrective round registers as coverage growing and the run converges.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_tool.dart';
import 'package:llamaseek/Models/research_ledger.dart';
import 'package:llamaseek/Services/search_agent.dart';
import 'package:llamaseek/Services/web_search_service.dart';
import 'package:llamaseek/Utils/text_similarity.dart';

/// The user's message. Deliberately digit-free: `_requestedInstances` is
/// taken from it, so there is nothing for `_isDifferentRequestedInstance`
/// to split the "2025" queries on and every query below groups.
const _question = 'What is the outlook for Brazilian inflation?';

/// The three queries the model runs before drafting. All group onto one
/// sub-goal, spending `perSubGoalBudget` (3) on it.
const _q1 = 'Brazil inflation rate 2025 forecast';
const _q2 = 'Brazil inflation rate 2025 estimate';
const _q3 = 'Brazil inflation rate 2025 projection';

/// What the completeness gate reports the draft left unaddressed.
const _gap = 'Brazil inflation rate forecast for next year';

WebSearchResult _hit(String query) => WebSearchResult(
      title: 'Result for $query',
      snippet: 'Figures for $query.',
      url: 'https://example.invalid/${query.hashCode}',
      chunks: ['Reported figure for $query is 4.2 percent.'],
    );

/// One full offline run. The model is scripted: two grouped tool calls,
/// then a third, then a draft, then a verbatim search for the gap the gate
/// just demanded, then prose forever.
class _RunRecord {
  final List<String> executedQueries = [];
  final List<String> briefs = [];
  final List<({String query, String reason})> skipped = [];
  final List<List<SubGoal>> ledgerSnapshots = [];

  /// Per-sub-goal search counts as they stood at each ledger publish.
  /// [SubGoal] is mutable and a snapshot list aliases the live objects, so
  /// reading counts off [ledgerSnapshots] after the run reports the FINAL
  /// state for every round — useless for saying what the panel showed while
  /// the run was still going.
  final List<List<int>> searchCountsAtUpdate = [];

  late final SearchAgentOutcome outcome;
}

Future<_RunRecord> _drive({required int perSubGoalBudget}) async {
  final record = _RunRecord();
  var turn = 0;

  OllamaMessage toolCall(String query) => OllamaMessage(
        '',
        role: OllamaMessageRole.assistant,
        toolCalls: [
          OllamaToolCall(name: 'web_search', arguments: {'query': query}),
        ],
      );

  final agent = SearchAgent(
    perSubGoalBudget: perSubGoalBudget,
    streamTurn: (request) async* {
      record.briefs.add(request.researchBrief);
      switch (turn++) {
        case 0:
          yield OllamaMessage(
            '',
            role: OllamaMessageRole.assistant,
            toolCalls: [
              OllamaToolCall(name: 'web_search', arguments: {'query': _q1}),
              OllamaToolCall(name: 'web_search', arguments: {'query': _q2}),
            ],
          );
        case 1:
          yield toolCall(_q3);
        case 2:
          yield OllamaMessage('Draft answer about Brazilian inflation.',
              role: OllamaMessageRole.assistant);
        case 3:
          // The model does exactly what _gapNotice told it to.
          yield toolCall(_gap);
        default:
          yield OllamaMessage('Final answer about Brazilian inflation.',
              role: OllamaMessageRole.assistant);
      }
    },
    search: (request) async {
      record.executedQueries.add(request.query);
      return [_hit(request.query)];
    },
    // One gap, on the first (and only) draft.
    assessCoverage: (_) async => const [_gap],
  );

  record.outcome = await agent.run(
    history: [OllamaMessage(_question, role: OllamaMessageRole.user)],
    listener: SearchAgentListener(
      onSearchSkipped: (query, reason) =>
          record.skipped.add((query: query, reason: reason)),
      onLedgerUpdate: (_, snapshot) {
        record.ledgerSnapshots.add(snapshot);
        record.searchCountsAtUpdate.add([for (final g in snapshot) g.searchCount]);
      },
    ),
  );
  return record;
}

void main() {
  group('similarity preconditions', () {
    test('every query and the gate\'s gap land in the grouping band', () {
      for (final q in [_q2, _q3, _gap]) {
        final score = trigramJaccard(_q1, q);
        expect(score, greaterThanOrEqualTo(0.40),
            reason: '"$q" scored $score against "$_q1" — at or above '
                'ResearchLedger._groupingThreshold, so findMatch calls it the '
                'same sub-goal');
        expect(score, lessThan(0.75),
            reason: '"$q" scored $score — BELOW SearchAgent'
                '._ledgerDupeSimilarityThreshold, so it is not refused as a '
                'near-verbatim rephrasing; only the per-sub-goal budget can '
                'refuse it');
      }
    });

    test('the user question has no digits for the instance guard to split on',
        () {
      expect(numericTokens(_question), isEmpty,
          reason: 'ResearchLedger._isDifferentRequestedInstance reads the '
              'digit-runs the USER typed; with none, the "2025" in the model\'s '
              'own queries cannot keep them apart');
    });
  });

  group('openGap reopens the searched sub-goal instead of erasing the gap',
      () {
    test('openGap keeps one sub-goal and files the gap on it as an open item',
        () {
      final ledger =
          ResearchLedger(objective: _question, userQuestion: _question);
      final searched = ledger.upsert(_q1);
      ledger.recordEvidence(searched, sourceIdStart: 1, sourceIdEnd: 3);

      final filed = ledger.openGap(_gap);

      expect(identical(filed, searched), isTrue,
          reason: 'openGap still reuses the sub-goal findMatch hit rather than '
              'spawning a lookalike beside it');
      expect(ledger.subGoals, hasLength(1),
          reason: 'and still bills no search: the gap is recorded ON the '
              'sub-goal, not as a second entry');
      expect(filed.outstandingGaps, [_gap],
          reason: 'the gate\'s verdict is now written down in the gate\'s own '
              'words, which is the fact all three downstream mechanisms were '
              'missing');
      expect(ledger.searchedSubGoalCount, 0,
          reason: 'a sub-goal the gate has just said is uncovered is not '
              'covered ground, so the corrective round can register as '
              'coverage growing when it lands');

      final brief = ledger.renderBrief();
      expect(brief, contains('- [ ]'),
          reason: 'the brief the corrective turn reads carries an open item '
              'for the stopping rule\'s "search only to close a specific [ ] '
              'item" to point at');
      expect(brief, contains(_gap),
          reason: 'worded as the gate worded it, so the model can act on the '
              'same text _gapNotice orders it to close');
      expect(brief, isNot(contains('- [x]')),
          reason: 'and nothing on the checklist claims that ground is covered '
              'while the gap is outstanding');
      expect(brief, contains(_q1),
          reason: 'the search that DID run is still named — the gap notice '
              'tells the model to keep everything it already established');
      expect(brief, contains('[1][2][3]'),
          reason: 'and its source ids survive, so the model keeps citing '
              'evidence that is still real');
    });

    test('recordEvidence closes the gap and the item ticks again', () {
      final ledger =
          ResearchLedger(objective: _question, userQuestion: _question);
      final searched = ledger.upsert(_q1);
      ledger.recordEvidence(searched, sourceIdStart: 1, sourceIdEnd: 3);
      final filed = ledger.openGap(_gap);

      ledger.recordEvidence(filed, sourceIdStart: 4, sourceIdEnd: 4);

      expect(filed.outstandingGaps, isEmpty,
          reason: 'landing sources is the only thing the harness can do about '
              'a reopening, so it closes it');
      expect(ledger.renderBrief(), contains('- [x]'),
          reason: 'and the checklist stops demanding a search it has now had');
      expect(ledger.searchedSubGoalCount, 1,
          reason: 'the sub-goal is covered ground again, which is what makes '
              'the corrective round count as broadening coverage');
    });
  });

  group('end to end: the harness runs the search it demanded', () {
    late _RunRecord run;

    setUpAll(() async {
      run = await _drive(perSubGoalBudget: SearchAgent.defaultPerSubGoalBudget);
    });

    test('the three pre-draft queries all bill to one sub-goal', () {
      expect(run.executedQueries.take(3), orderedEquals([_q1, _q2, _q3]),
          reason: 'the scripted research rounds ran as written');
      expect(SearchAgent.defaultPerSubGoalBudget, 3,
          reason: 'the script is built to spend exactly the default budget '
              'before the completeness gate ever runs');
      expect(run.searchCountsAtUpdate.map((c) => c.length), everyElement(lessThan(2)),
          reason: 'three distinct queries collapsed onto one sub-goal and '
              'nothing ever added a second entry beside it');
      expect(
          [for (final counts in run.searchCountsAtUpdate) if (counts.isNotEmpty) counts.single],
          orderedEquals([2, 3, 3, 4]),
          reason: 'the two grouped queries of round 1, the third (spending '
              'perSubGoalBudget exactly), the gate\'s own publish, and then '
              'the corrective search — which the spent budget no longer '
              'refuses');
    });

    test('the gap the gate demanded is searched', () {
      expect(run.executedQueries, contains(_gap),
          reason: 'the model asked for the gap verbatim, exactly as '
              'SearchAgent._gapNotice instructed, and the request reached the '
              'search backend');
      expect(run.executedQueries, hasLength(4),
          reason: 'the corrective round executed exactly the one search it '
              'was told to');
    });

    test('nothing is refused', () {
      expect(run.skipped, isEmpty,
          reason: 'SearchAgent._isLedgerBlocked returns false for a sub-goal '
              'carrying an outstanding gap, one case over from the '
              'searchCount == 0 guard — so neither the exact-repeat test, the '
              'similarity test nor `matched.searchCount >= perSubGoalBudget` '
              'gets to refuse the search the harness itself ordered');
    });

    test('the gap is closed by real evidence, not forgotten', () {
      // Snapshots alias the run's live SubGoals, so this reads the FINAL
      // state — mid-run gap visibility is proven through `briefs` below.
      final finalSnapshot = run.ledgerSnapshots.last;
      expect(finalSnapshot, hasLength(1),
          reason: 'the gap never needed an entry of its own: it was filed on '
              'the sub-goal it belongs to');
      expect(finalSnapshot.single.outstandingGaps, isEmpty,
          reason: 'and the corrective search closed it');
      expect(finalSnapshot.single.ranges, hasLength(4),
          reason: 'with its own block of source ids appended to the three the '
              'pre-draft searches gathered');
      expect(finalSnapshot.single.status, SubGoalStatus.searched,
          reason: 'so the panel and the brief agree the ground is covered — '
              'this time because it is');
    });

    test('the corrective turn is handed a brief with the gap open', () {
      // briefs[3] is the turn that reads _gapNotice and emits the gap query.
      final correctiveBrief = run.briefs[3];
      expect(correctiveBrief, contains('- [ ] "$_gap"'),
          reason: 'the gate\'s finding is on the checklist, in its own words, '
              'unticked');
      expect(correctiveBrief, isNot(contains('- [x]')),
          reason: 'and nothing claims that ground is already covered while '
              'the gap is outstanding');
      expect(correctiveBrief, contains(_q1),
          reason: 'the earlier search is still named, so the model can see '
              'what it already tried');
      expect(correctiveBrief, contains('[1][2][3]'),
          reason: 'and still cites its three sources — "keep everything you '
              'already established" points at evidence that is really there');
      expect(correctiveBrief, contains(ResearchLedger.stoppingRule),
          reason: 'the stopping rule\'s "search only to close a specific [ ] '
              'item" now points at exactly the item _gapNotice orders closed: '
              'brief and notice finally say the same thing');
    });

    test('the run converges instead of being blamed on the model', () {
      expect(run.outcome.reason, SearchTerminationReason.converged,
          reason: 'closing the gap made searchedSubGoalCount grow, so the '
              'round the harness demanded reset the stall counters instead of '
              'advancing them, and the model stopped searching on its own');
      expect(run.outcome.searchCount, 4,
          reason: 'three pre-draft searches plus the corrective one — the '
              'evidence the refused run never got');
    });
  });

  group(
      'control: the per-sub-goal budget no longer decides whether the gap is '
      'searched', () {
    test('one more unit of budget changes nothing about the outcome',
        () async {
      final run = await _drive(
          perSubGoalBudget: SearchAgent.defaultPerSubGoalBudget + 1);

      expect(run.executedQueries, orderedEquals([_q1, _q2, _q3, _gap]),
          reason: 'the identical script executes the identical searches with '
              'budget to spare — so the budget is no longer what decides '
              'whether the gate\'s gap is researched');
      expect(run.skipped, isEmpty,
          reason: 'and nothing else in the plan pipeline objects to the query '
              'either');
      expect(run.outcome.reason, SearchTerminationReason.converged,
          reason: 'same reason as the budget-exact run: a reopened sub-goal '
              'is not counted as covered ground, so closing it broadens '
              'coverage whatever the budget was');
      expect(run.outcome.searchCount, 4);
    });
  });
}
