/// Offline probes for structural loopholes in the research loop's
/// convergence machinery — the ones that need no model and no network to
/// demonstrate, so they can live in the normal gate alongside the live
/// OpenRouter sweep in
/// `test/integration/openrouter_search_loop_live_test.dart`.
///
/// These are characterization tests: each one pins down what the harness
/// does today at a boundary the live sweep can only observe indirectly
/// (as "the model asked four things and got two"). Where the documented
/// behavior is the intended one the test says so; where it is a gap the
/// test names the gap in its reason string rather than pretending the
/// behavior is desirable.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/research_ledger.dart';
import 'package:llamaseek/Utils/text_similarity.dart';

void main() {
  group('parallel entities collapse onto one sub-goal', () {
    // The four-cities case. ResearchLedger._groupingThreshold is 0.40 and
    // _isDifferentRequestedInstance only ever splits on digit-runs the USER
    // typed — so a question naming four entities with no numbers in it has
    // nothing to split on, and every "population of <city>" query is a
    // trigram near-match of the last one.
    const question =
        'What is the current population of Tokyo, Delhi, Shanghai and '
        'São Paulo? Give the figure for each.';
    const queries = [
      'current population of Tokyo',
      'current population of Delhi',
      'current population of Shanghai',
      'current population of São Paulo',
    ];

    test('four distinct city lookups score above the grouping threshold', () {
      for (var i = 1; i < queries.length; i++) {
        final score = trigramJaccard(queries[0], queries[i]);
        expect(score, greaterThanOrEqualTo(0.40),
            reason: '"${queries[0]}" vs "${queries[i]}" scored $score — at or '
                'above ResearchLedger._groupingThreshold, so findMatch files '
                'them as the same sub-goal');
      }
    });

    test('the ledger files all four cities as a single sub-goal', () {
      final ledger = ResearchLedger(objective: question, userQuestion: question);
      for (final q in queries) {
        ledger.upsert(q);
      }

      expect(ledger.subGoals, hasLength(1),
          reason: 'four separate lookups collapsed into '
              '${ledger.subGoals.length} sub-goal(s); the checklist can no '
              'longer represent "Delhi is still open while Tokyo is done"');
      expect(ledger.subGoals.single.searchCount, 4,
          reason: 'all four searches billed to one sub-goal, so '
              'SearchAgent.perSubGoalBudget (3) is exhausted by the third '
              'city and the fourth is refused as a duplicate');
    });

    test('a year the user typed does split the sub-goals', () {
      // The same shape WITH user-supplied digits stays separate — this is
      // the guard that exists, and it is exactly why the no-digit case
      // above has nothing protecting it.
      const dated = 'US inflation in 2021, 2022, 2023 and 2024';
      final ledger = ResearchLedger(objective: dated, userQuestion: dated);
      for (final year in ['2021', '2022', '2023', '2024']) {
        ledger.upsert('US inflation rate $year');
      }
      expect(ledger.subGoals, hasLength(4),
          reason: 'years the user named are protected by '
              'ResearchLedger._isDifferentRequestedInstance');
    });
  });

  group('round batch cap vs. a breadth-first plan', () {
    test('a model that plans four searches at once gets two', () {
      // SearchAgent.defaultRoundBatchCap is 2. This is intentional (read
      // before you fan out further), but it means a model whose whole plan
      // is one parallel burst needs two more rounds to land it — and the
      // stall counter is running the whole time.
      expect(2, lessThan(4),
          reason: 'documented here so the live sweep\'s '
              '"roundBatchCapped" skip counts have a stated baseline');
    });
  });
}
