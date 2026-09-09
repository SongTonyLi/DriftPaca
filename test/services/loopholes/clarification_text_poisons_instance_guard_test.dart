/// Probe: model-authored clarification prose becomes "the instances the
/// user asked about".
///
/// `ResearchLedger._requestedInstances` is `numericTokens(userQuestion)`,
/// and its doc comment states the safety argument explicitly: the digits
/// must be the USER's, never a model's invention, which is why they are
/// deliberately not taken from the model-derived `objective`. But
/// `SearchAgent.run` sets `userQuestion: clarified.question`, and
/// `ResearchClarification.clarifiedQuestion` appends the derivation
/// model's clarification QUESTION verbatim on top of the user's picks.
/// Every digit-run in that model prose — including the readings the user
/// explicitly declined — is then indistinguishable from a year the user
/// typed, and `_isDifferentRequestedInstance` hard-skips any sub-goal
/// lacking it.
///
/// The channel is wider than digits: `_requestedInstances` also reads the
/// capitalised names out of `userQuestion` (see `properNounTokens`), so the
/// model's clarification question contributes any names it happens to use
/// on exactly the same terms. That does not change the defect these tests
/// document — it is the model's prose reaching ground truth at all, not
/// which tokens are read out of it once it gets there.
///
/// These tests are offline: fake `streamTurn`, fake `search`, fake
/// `deriveGoal`, fake `askClarification`. No network, no model.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_tool.dart';
import 'package:llamaseek/Models/research_ledger.dart';
import 'package:llamaseek/Services/search_agent.dart';
import 'package:llamaseek/Services/web_search_service.dart';
import 'package:llamaseek/Utils/text_similarity.dart';

/// What the user typed. Contains no digits at all, so on its own
/// `_requestedInstances` is empty and every near-duplicate re-ask groups.
const _raw = 'How is Apple doing this quarter?';

/// What the derivation model asked back. `goalDerivationInstruction`
/// invites exactly this ("which time period") and tells the model to keep
/// the user's "numbers, dates", so a quarter-naming question is the
/// expected shape.
const _clarifyQuestion = 'Which quarter do you mean — Q1 2025, Q4 2024, or '
    'Q3 2024?';

/// The single reading the user actually picked.
const _picked = 'Q1 2025';

/// The model's thrash: the same lookup, re-asked with a different
/// quarter/year label each round. Only the first names the quarter the
/// user picked; Q4 2024 and Q3 2024 are readings the user DECLINED, and
/// Q1 2024 / Q4 2025 / Q3 2025 were never on the card at all — they are
/// recombinations of digit-runs that only ever appeared in the model's
/// own clarification prose.
const _thrash = [
  'Apple revenue Q1 2025',
  'Apple revenue Q4 2024',
  'Apple revenue Q3 2024',
  'Apple revenue Q1 2024',
  'Apple revenue Q4 2025',
  'Apple revenue Q3 2025',
];

void main() {
  group('clarification prose is read as user-named instances', () {
    test('digits the user never chose enter numericTokens(userQuestion)', () {
      final polluted = ResearchClarification.clarifiedQuestion(
          _raw, _clarifyQuestion, const [_picked]);

      expect(numericTokens(_raw), isEmpty,
          reason: 'the user typed no digits, so the ledger should have no '
              'requested instances to split sub-goals on at all');
      expect(numericTokens('$_raw $_picked'), {'1', '2025'},
          reason: 'folding in the option the user PICKED is the documented, '
              'deliberate behaviour and contributes only 1 and 2025');
      expect(numericTokens(polluted), {'1', '2025', '4', '2024', '3'},
          reason: 'but clarifiedQuestion also concatenates the model\'s own '
              'question verbatim, so 4, 2024 and 3 — digits belonging solely '
              'to the readings the user declined — are now indistinguishable '
              'from years the user typed');
    });

    test('the same digits placed in the objective are correctly ignored', () {
      // The guarantee _requestedInstances documents, still intact on the
      // channel it was written for: a model-derived restatement carrying
      // the identical text does not split anything.
      final viaObjective = ResearchLedger(
        objective: '$_raw\n\n(Clarified — "$_clarifyQuestion": $_picked)',
        userQuestion: _raw,
      );
      viaObjective.upsert(_thrash[0]);

      expect(viaObjective.findMatch(_thrash[1]), isNotNull,
          reason: 'digits in the OBJECTIVE do not become requested '
              'instances, so the Q4 2024 re-ask still groups — the '
              'clarification channel is the one that bypasses this');
    });
  });

  group('ledger grouping collapses under the polluted question', () {
    ResearchLedger ledgerFor(String userQuestion) {
      final ledger = ResearchLedger(
          objective: 'Apple\'s performance this quarter',
          userQuestion: userQuestion);
      ledger.upsert(_thrash[0]);
      return ledger;
    }

    test('every thrash query is a trigram near-duplicate of the first', () {
      for (var i = 1; i < _thrash.length; i++) {
        final score = trigramJaccard(_thrash[0], _thrash[i]);
        expect(score, greaterThanOrEqualTo(0.40),
            reason: '"${_thrash[i]}" scores $score against "${_thrash[0]}" — '
                'above ResearchLedger._groupingThreshold, so grouping is what '
                'the trigram layer wants; only _isDifferentRequestedInstance '
                'can override it');
      }
    });

    test('raw question: all six re-asks land on one sub-goal', () {
      final ledger = ledgerFor(_raw);
      for (final q in _thrash.skip(1)) {
        ledger.upsert(q);
      }
      expect(ledger.subGoals, hasLength(1),
          reason: 'with the user\'s own digit-free question the harness '
              'recognises the whole thing as one question re-asked, which is '
              'what the per-sub-goal budget and the stall counter are sized '
              'for');
    });

    test('picks-only clarification: still one sub-goal', () {
      // The behaviour clarifiedQuestion's doc comment argues for — the
      // user's explicit choice folded into the ground truth — is harmless
      // on its own.
      final ledger = ledgerFor('$_raw $_picked');
      for (final q in _thrash.skip(1)) {
        ledger.upsert(q);
      }
      expect(ledger.subGoals, hasLength(1),
          reason: 'folding in only what the user picked keeps every re-ask '
              'grouped, so the defect is not the picks — it is the model\'s '
              'question text riding along with them');
    });

    test('full clarified question: six sub-goals, six fresh budgets', () {
      final ledger = ledgerFor(ResearchClarification.clarifiedQuestion(
          _raw, _clarifyQuestion, const [_picked]));
      for (final q in _thrash.skip(1)) {
        ledger.upsert(q);
      }
      expect(ledger.subGoals, hasLength(6),
          reason: 'each label recombined out of the clarification prose '
              'reads as a distinct instance the user asked for, so every one '
              'gets its own sub-goal and its own perSubGoalBudget');
      expect(ledger.subGoals.every((g) => g.searchCount == 1), isTrue,
          reason: 'and none of them has spent more than one search, so '
              'SearchAgent._isLedgerBlocked will refuse nothing');
      expect(
          ledger.subGoals.map((g) => g.query),
          containsAll(<String>['Apple revenue Q4 2024', 'Apple revenue Q3 2024']),
          reason: 'two of the sub-goals now being funded are precisely the '
              'readings the user rejected on the clarification card');
    });
  });

  group('end to end: answering the card defeats the anti-thrash guard', () {
    /// Runs a full SearchAgent over [_thrash], one query per round. The
    /// two runs differ ONLY in what the user does with the clarification
    /// card: [picks] empty means they skipped it.
    Future<({int searches, List<String> subGoals, SearchTerminationReason reason})>
        runWith(List<String> picks) async {
      var next = 0;
      final subGoals = <String>[];
      final agent = SearchAgent(
        streamTurn: (request) async* {
          if (!request.toolsEnabled || next >= _thrash.length) {
            yield OllamaMessage('Apple had a fine quarter.',
                role: OllamaMessageRole.assistant);
            return;
          }
          yield OllamaMessage('',
              role: OllamaMessageRole.assistant,
              toolCalls: [
                OllamaToolCall(
                    name: 'web_search',
                    arguments: {'query': _thrash[next++]}),
              ]);
        },
        search: (request) async => [
          WebSearchResult(
            title: 'Apple results',
            snippet: 'apple results',
            url: 'https://example.invalid/${Uri.encodeComponent(request.query)}',
            chunks: const ['Apple reported revenue for the quarter.'],
          ),
        ],
        deriveGoal: (_) async => const ResearchGoal(
          statement: 'Apple\'s performance in the quarter the user means',
          clarification: ResearchClarification(
            question: _clarifyQuestion,
            options: [_picked, 'Q4 2024', 'Q3 2024'],
          ),
        ),
        askClarification: (_) async => picks,
      );

      final outcome = await agent.run(
        history: [OllamaMessage(_raw, role: OllamaMessageRole.user)],
        listener: SearchAgentListener(
          onLedgerUpdate: (_, snapshot) {
            subGoals
              ..clear()
              ..addAll(snapshot.map((g) => g.query));
          },
        ),
      );
      return (
        searches: outcome.searchCount,
        subGoals: subGoals,
        reason: outcome.reason,
      );
    }

    test('skipping the card: the run recognises the thrash and stops',
        () async {
      final skipped = await runWith(const []);

      expect(skipped.subGoals, hasLength(1),
          reason: 'with the user\'s own question as ground truth every '
              're-ask groups onto one sub-goal');
      expect(skipped.searches, 3,
          reason: 'so after two rounds that covered no new ground '
              'roundsSinceCoverageGrew hits stallLimit and research closes — '
              'exactly the anti-thrash behaviour _isDifferentRequestedInstance '
              'documents');
      expect(skipped.reason, SearchTerminationReason.unproductiveRounds,
          reason: 'and the run is correctly reported as having gone in '
              'circles');
    });

    test('answering the card: the identical thrash runs unchecked', () async {
      final clarified = await runWith(const [_picked]);

      expect(clarified.subGoals, hasLength(6),
          reason: 'the same six queries now open six sub-goals, because the '
              'quarter labels in the model\'s clarification question are '
              'treated as instances the user named');
      expect(clarified.searches, 6,
          reason: 'every round opened a brand-new sub-goal, so '
              'broadenedCoverage was true every round and the stall counter '
              'never fired: the run spent twice the searches of the skipped '
              'run on the same six near-duplicate queries');
      expect(clarified.searches, greaterThan(3),
          reason: 'the user answering a clarification card — the one place '
              'the loop asks a human to make the run MORE targeted — is what '
              'disabled the guard');
      expect(clarified.reason, SearchTerminationReason.converged,
          reason: 'nothing in the harness ended this run: it stopped only '
              'because the scripted model ran out of quarter labels to '
              'permute, where the skipped run was stopped by the stall '
              'counter after three searches');
      expect(
          clarified.subGoals,
          containsAll(<String>[
            'Apple revenue Q4 2024',
            'Apple revenue Q3 2024',
            'Apple revenue Q4 2025',
          ]),
          reason: 'search budget was spent on two readings the user '
              'explicitly declined and on a quarter that appeared on neither '
              'the card nor in anything the user typed');
    });
  });
}
