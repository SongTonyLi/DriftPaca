/// Guarantee: only what the USER typed or ticked names an instance. The
/// clarification card's question text never does.
///
/// `ResearchLedger._requestedInstances` rests its whole safety argument on
/// the instances being the user's and never a model's invention, which is
/// why they are deliberately not taken from the model-derived `objective`.
/// That argument covers the clarification QUESTION word for word: it is
/// the derivation model's own prose, and a question that enumerates the
/// readings ("Q1 2025, Q4 2024, or Q3 2024?") would otherwise hand the
/// ledger exactly the invented year variants
/// `_isDifferentRequestedInstance` exists to group away — the readings the
/// user declined included, each with a sub-goal and a fresh search budget
/// of its own.
///
/// So `SearchAgent.run` splits the record it gets back from `_clarify`:
/// `ResearchLedger.userQuestion` is the user's message verbatim,
/// `ResearchLedger.clarificationPicks` carries the options they actually
/// ticked (the one piece of model-authored text they endorsed, by
/// selecting it), and the composed `clarifiedQuestion` — picks under the
/// model's question — goes only to the completeness gate, which reads
/// prose and needs the refined reading spelled out.
///
/// The channel these tests close was wider than digits:
/// `_requestedInstances` also reads capitalised names (see
/// `properNounTokens`), so the model's clarification question contributed
/// any name it happened to use on exactly the same terms. Both token kinds
/// are pinned below, on both sides of the split — excluded from the
/// question, kept for the picks.
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

/// What the user typed. Contains no digits at all and names one thing, so
/// on its own `_requestedInstances` is empty and every near-duplicate
/// re-ask groups.
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
  group('clarification prose is not read as user-named instances', () {
    test('digits the user never chose stay out of the ledger\'s instances',
        () {
      final composed = ResearchClarification.clarifiedQuestion(
          _raw, _clarifyQuestion, const [_picked]);

      expect(numericTokens(_raw), isEmpty,
          reason: 'the user typed no digits, so the ledger should have no '
              'requested instances to split sub-goals on at all');
      expect(numericTokens(_picked), {'1', '2025'},
          reason: 'the option the user PICKED is the documented, deliberate '
              'exception and contributes only 1 and 2025');
      expect(numericTokens(composed), {'1', '2025', '4', '2024', '3'},
          reason: 'the composed string still carries 4, 2024 and 3 — digits '
              'belonging solely to the readings the user declined — because '
              'it concatenates the model\'s own question verbatim for the '
              'completeness gate. That is exactly why it is no longer what '
              'the ledger reads instances out of');
      expect(properNounTokens(composed), containsAll(<String>['q4', 'q3']),
          reason: 'and the same string offers the model\'s quarter labels as '
              'NAMES too, so narrowing the source to digits alone would not '
              'have closed this');

      // What the ledger actually gets built with now: the message the user
      // typed, plus the one option they ticked.
      final ledger = ResearchLedger(
        objective: 'Apple\'s performance this quarter',
        userQuestion: _raw,
        clarificationPicks: const [_picked],
      );
      ledger.upsert(_thrash[0]);

      expect(ledger.findMatch(_thrash[1]), isNotNull,
          reason: '"${_thrash[1]}" is a reading the user DECLINED; its digits '
              'exist only in the model\'s question, so it must still group '
              'onto the sub-goal it is a re-ask of');
      expect(ledger.findMatch(_thrash[3]), isNotNull,
          reason: '"${_thrash[3]}" was never even on the card — it is a '
              'recombination of digits out of the model\'s prose, which is '
              'the model inventing year variants and precisely what '
              '_isDifferentRequestedInstance groups away');
    });

    test('the same digits placed in the objective are correctly ignored', () {
      // The guarantee _requestedInstances documents, on the channel it was
      // written for: a model-derived restatement carrying the identical
      // text does not split anything. The clarification channel above now
      // behaves the same way rather than bypassing it.
      final viaObjective = ResearchLedger(
        objective: '$_raw\n\n(Clarified — "$_clarifyQuestion": $_picked)',
        userQuestion: _raw,
      );
      viaObjective.upsert(_thrash[0]);

      expect(viaObjective.findMatch(_thrash[1]), isNotNull,
          reason: 'digits in the OBJECTIVE do not become requested '
              'instances, so the Q4 2024 re-ask still groups');
    });
  });

  group('ledger grouping survives an answered clarification', () {
    ResearchLedger ledgerFor(String userQuestion,
        {List<String> picks = const []}) {
      final ledger = ResearchLedger(
        objective: 'Apple\'s performance this quarter',
        userQuestion: userQuestion,
        clarificationPicks: picks,
      );
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
      final ledger = ledgerFor(_raw, picks: const [_picked]);
      for (final q in _thrash.skip(1)) {
        ledger.upsert(q);
      }
      expect(ledger.subGoals, hasLength(1),
          reason: 'the one option the user ticked pins Q1 2025, and every '
              'other label the model tried is either absent from their pick '
              'or already inside it — a re-ask, not a new instance');
    });

    test('answering the card: still one sub-goal, one budget', () {
      // Built the way SearchAgent.run now builds it: verbatim question,
      // ticked options, and nothing composed from the model's prose.
      final ledger = ledgerFor(_raw, picks: const [_picked]);
      for (final q in _thrash.skip(1)) {
        ledger.upsert(q);
      }

      expect(ledger.subGoals, hasLength(1),
          reason: 'the quarter labels recombined out of the clarification '
              'question are the model\'s own invention, so they group instead '
              'of each buying a sub-goal and a fresh perSubGoalBudget');
      expect(ledger.subGoals.single.query, _thrash[0],
          reason: 'and the sub-goal is still the one the first query opened');
      expect(ledger.subGoals.single.searchCount, 6,
          reason: 'all six attempts are billed to that one budget, so '
              'SearchAgent._isLedgerBlocked refuses the later re-asks rather '
              'than funding them');
      expect(ledger.subGoals.map((g) => g.query),
          isNot(contains('Apple revenue Q4 2024')),
          reason: 'no sub-goal — and so no search budget — is ever opened '
              'for a reading the user looked at and declined');
    });

    test('two picked options are two instances', () {
      // The other direction, and the reason picks are kept as an instance
      // source at all: a user who ticks two readings is asking two
      // questions, exactly as if they had typed both quarters.
      final ledger = ledgerFor(_raw, picks: const [_picked, 'Q4 2024']);

      expect(ledger.findMatch(_thrash[1]), isNull,
          reason: 'Q4 2024 is now one of the readings the user chose, so a '
              'query naming it must not be folded into the Q1 2025 sub-goal '
              'and share its budget');
      ledger.upsert(_thrash[1]);
      expect(ledger.subGoals, hasLength(2),
          reason: 'two ticked options are two sub-goals, each with its own '
              'budget and its own line on the checklist');
    });

    test('two picked names are two instances, exactly as two picked years are',
        () {
      // Same rule on the other token kind. A card that disambiguates WHICH
      // ENTITY carries no digits at all, so if picks contributed only
      // digit-runs the two cities the user explicitly chose would collapse
      // onto one sub-goal — the four-cities failure, re-opened through the
      // clarification path.
      final cities = ResearchLedger(
        objective: 'Population of the city the user means',
        userQuestion: 'What is the current population there?',
        clarificationPicks: const ['Tokyo', 'Delhi'],
      );
      final tokyo = cities.upsert('current population of Tokyo');

      expect(cities.findMatch('current population of Delhi'), isNull,
          reason: 'the two queries are trigram near-duplicates, so only the '
              'user having ticked both cities can keep them apart');
      expect(cities.findMatch('current population of Osaka'), same(tokyo),
          reason: 'while a city the card never offered is the model '
              'wandering off, and still groups');
    });
  });

  group('end to end: answering the card keeps the anti-thrash guard', () {
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

    test('answering the card: the identical thrash is still stopped', () async {
      final clarified = await runWith(const [_picked]);
      final skipped = await runWith(const []);

      expect(clarified.subGoals, hasLength(1),
          reason: 'the same six queries still open one sub-goal: the quarter '
              'labels live in the model\'s clarification question, and that '
              'question never reaches the instance split');
      expect(clarified.searches, 3,
          reason: 'the stall counter fires on schedule, so the run costs '
              'three searches and not one per label the model can permute');
      expect(clarified.reason, SearchTerminationReason.unproductiveRounds,
          reason: 'and the harness — not the scripted model running out of '
              'labels — is what ended it');
      expect(
          clarified.subGoals,
          isNot(anyElement(anyOf(
            'Apple revenue Q4 2024',
            'Apple revenue Q3 2024',
            'Apple revenue Q4 2025',
          ))),
          reason: 'no search budget is opened for the two readings the user '
              'declined, nor for a quarter that appeared on neither the card '
              'nor in anything the user typed');

      expect(
          (clarified.searches, clarified.subGoals.length, clarified.reason),
          (skipped.searches, skipped.subGoals.length, skipped.reason),
          reason: 'answering the clarification card must not change how the '
              'harness groups the model\'s own quarter permutations — only '
              'what the user ticked is theirs, and here they ticked the '
              'quarter the first query already names');
    });
  });
}
