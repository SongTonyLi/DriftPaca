/// Probe: the completeness gate's own gap is erased by the ledger and its
/// corrective search is then refused by the per-sub-goal budget.
///
/// `SearchAgent.run` files every gap the completeness gate returns with
/// `ResearchLedger.openGap`, which calls `findMatch` first and, on a hit,
/// returns the EXISTING sub-goal untouched. So a gap whose wording is at or
/// above `ResearchLedger._groupingThreshold` (0.40) trigram-similar to a
/// sub-goal that has ALREADY been searched adds no checklist entry at all:
/// the brief re-rendered for the corrective turn shows every item `[x]`
/// plus the stopping rule "An [x] item counts as covered", while the
/// `_gapNotice` shoved into the same transcript says "Search for them now".
///
/// When the model obeys, `_planSearches` matches the gap query back onto
/// that same searched sub-goal and `_isLedgerBlocked` refuses it. The
/// `if (matched.searchCount == 0) return false;` guard at
/// search_agent.dart:1171 — added, per its own comment, precisely so "the
/// harness refused the very search it had just demanded" could not recur —
/// only covers gaps that landed on an UNSEARCHED sub-goal, so a gap that
/// landed on a searched one falls through to
/// `matched.searchCount >= perSubGoalBudget` and is refused.
///
/// The refused round executes nothing, so `run()` advances both stall
/// counters, `_canSearch` goes false, the tool is withdrawn, and
/// `_terminationReason` reports `unproductiveRounds` — a run that ends
/// having never searched the gap its own gate identified, with a checklist
/// that claims full coverage and never tells the user otherwise.
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
      onLedgerUpdate: (_, snapshot) => record.ledgerSnapshots.add(snapshot),
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

  group('root cause: openGap erases a gap that lands on a searched sub-goal',
      () {
    test('openGap returns the searched sub-goal unchanged and adds no entry',
        () {
      final ledger =
          ResearchLedger(objective: _question, userQuestion: _question);
      final searched = ledger.upsert(_q1);
      ledger.recordEvidence(searched, sourceIdStart: 1, sourceIdEnd: 3);

      final filed = ledger.openGap(_gap);

      expect(identical(filed, searched), isTrue,
          reason: 'openGap called findMatch, hit the already-searched '
              'sub-goal, and returned it — the gap has no identity of its own');
      expect(ledger.subGoals, hasLength(1),
          reason: 'the completeness gate reported a gap and the ledger grew by '
              'zero entries, so nothing on the checklist represents it');
      expect(ledger.subGoals.single.status, SubGoalStatus.searched,
          reason: 'and the one entry that does exist is still [x], so the '
              'brief the corrective turn reads claims full coverage');
      expect(ledger.renderBrief(), isNot(contains('- [ ]')),
          reason: 'the rendered brief carries no open item at all, while '
              'ResearchLedger.stoppingRule in the same brief says "An [x] item '
              'counts as covered"');
      expect(ledger.renderBrief(), isNot(contains(_gap)),
          reason: 'the gap\'s own wording never appears in the brief the model '
              'is asked to act on');
    });
  });

  group('end to end: the harness refuses the search it just demanded', () {
    late _RunRecord run;

    setUpAll(() async {
      run = await _drive(perSubGoalBudget: SearchAgent.defaultPerSubGoalBudget);
    });

    test('the three pre-draft queries all bill to one sub-goal', () {
      expect(run.executedQueries.take(3), orderedEquals([_q1, _q2, _q3]),
          reason: 'the scripted research rounds ran as written');
      final beforeGap = run.ledgerSnapshots
          .lastWhere((s) => s.isNotEmpty && s.single.searchCount >= 3);
      expect(beforeGap, hasLength(1),
          reason: 'three distinct queries collapsed onto one sub-goal');
      expect(beforeGap.single.searchCount,
          SearchAgent.defaultPerSubGoalBudget,
          reason: 'so perSubGoalBudget is exactly spent before the '
              'completeness gate has even run');
    });

    test('the gap the gate demanded is never searched', () {
      expect(run.executedQueries, isNot(contains(_gap)),
          reason: 'the model asked for the gap verbatim, exactly as '
              'SearchAgent._gapNotice instructed, and no request ever reached '
              'the search stub');
      expect(run.executedQueries, hasLength(3),
          reason: 'the corrective round executed nothing at all');
    });

    test('it is refused as a near-duplicate of the sub-goal it landed on', () {
      final refusal = run.skipped.singleWhere((s) => s.query == _gap);
      expect(refusal.reason, contains('You already asked something very close'),
          reason: 'SearchAgent._isLedgerBlocked fell past its '
              'searchCount == 0 guard (the sub-goal HAD been searched) to '
              '`matched.searchCount >= perSubGoalBudget`, so the harness '
              'refused the very search it had just demanded');
      expect(refusal.reason, contains(_q1),
          reason: 'and told the model to consult a ledger line for a DIFFERENT '
              'question than the gap it was ordered to close');
    });

    test('no checklist entry ever represents the gap', () {
      final finalSnapshot = run.ledgerSnapshots.last;
      expect(finalSnapshot, hasLength(1),
          reason: 'the ledger never grew past the one grouped sub-goal, '
              'before or after the gate fired');
      expect(finalSnapshot.map((g) => g.query), isNot(contains(_gap)),
          reason: 'openGap swallowed the gap, so it exists nowhere the model '
              'or the UI can see it');
      expect(finalSnapshot.single.status, SubGoalStatus.searched,
          reason: 'every item is [x]: the user-facing panel and the model\'s '
              'brief both claim the goal is fully covered while the gate\'s '
              'own finding is unsearched');
    });

    test('the corrective turn is handed an all-[x] brief', () {
      // briefs[3] is the turn that reads _gapNotice and emits the gap query.
      final correctiveBrief = run.briefs[3];
      expect(correctiveBrief, contains('- [x] "$_q1"'),
          reason: 'the only checklist line is a ticked one');
      expect(correctiveBrief, isNot(contains('- [ ]')),
          reason: 'nothing is open, so the stopping rule\'s "search only to '
              'close a specific [ ] item" points at no item at all');
      expect(correctiveBrief, contains('An [x] item counts as covered'),
          reason: 'while the transcript alongside it says "Search for them '
              'now" — the two instructions handed to the same turn '
              'contradict each other');
    });

    test('the run is blamed on the model as unproductiveRounds', () {
      expect(run.outcome.reason, SearchTerminationReason.unproductiveRounds,
          reason: 'the round the harness itself emptied advanced the stall '
              'counters, _canSearch went false, and the run is reported as '
              'the model going in circles');
      expect(run.outcome.searchCount, 3,
          reason: 'well under maxSearches (15) and maxRounds (20) — no cost '
              'cap ended this run, the refusal did');
    });
  });

  group('control: only the per-sub-goal budget causes the refusal', () {
    test('one more unit of budget lets the same script search the gap',
        () async {
      final run = await _drive(
          perSubGoalBudget: SearchAgent.defaultPerSubGoalBudget + 1);

      expect(run.executedQueries, contains(_gap),
          reason: 'with budget to spare, the identical scripted turn DOES '
              'reach the search backend — so the refusal above is caused by '
              '`matched.searchCount >= perSubGoalBudget` and nothing else');
      expect(run.skipped.where((s) => s.query == _gap), isEmpty,
          reason: 'and nothing else in the plan pipeline objects to this query');
      // Scope note, kept as an assertion so it cannot rot: the grouping is
      // enough on its own to trip roundsSinceCoverageGrew (a search on an
      // already-searched sub-goal grows neither subGoals.length nor
      // searchedSubGoalCount), so `unproductiveRounds` is reported here too.
      // What the refusal above uniquely costs is the evidence: this run has
      // the gap's sources, the refused one has nothing.
      expect(run.outcome.reason, SearchTerminationReason.unproductiveRounds,
          reason: 'the stall counters trip either way — the defect proven is '
              'that the gate\'s gap is erased and its search refused, not that '
              'the refusal alone chose the termination reason');
      expect(run.outcome.searchCount, 4,
          reason: 'and the corrective search really did add evidence the '
              'refused run never got');
    });
  });
}
