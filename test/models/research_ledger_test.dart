import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/research_ledger.dart';

void main() {
  group('ResearchLedger.findMatch', () {
    test('matches an exact-normalized variant and a near-duplicate phrasing', () {
      final ledger = ResearchLedger(objective: 'objective');
      final goal = ledger.upsert('Vietnam GDP 2024');
      final parisGoal =
          ledger.upsert('Paris 2024 Summer Olympics gold medals USA count');

      expect(ledger.findMatch('vietnam   gdp 2024'), same(goal));
      // Measured near-duplicate pair from a real tool-calling run.
      expect(
        ledger.findMatch('Paris 2024 Olympic gold medal count USA'),
        same(parisGoal),
      );
      expect(ledger.findMatch('a totally unrelated query about pasta'), isNull);
    });

    test('splits a year the user asked about, but not one the model invented', () {
      // Both ledgers see the identical pair of queries. The only thing
      // that differs is whether the user's own question named the years —
      // which is exactly the line the instance split is drawn on, because
      // it is the one signal that separates "the user wants both years"
      // from "the model is wobbling between years on its own".
      const first = 'US inflation rate 2023';
      const second = 'US inflation rate 2024';

      final asked = ResearchLedger(
          objective: 'US inflation rate in 2023 and 2024?');
      asked.upsert(first);
      expect(asked.findMatch(second), isNull);
      asked.upsert(second);
      expect(asked.subGoals, hasLength(2),
          reason: 'a year the user listed is a question of its own');

      final invented = ResearchLedger(objective: 'US inflation rate lately?');
      final goal = invented.upsert(first);
      // 0.905 similarity, no year in the objective: still one sub-goal, so
      // the per-sub-goal budget and roundsSinceNewSubGoal still catch a
      // model that keeps re-asking one question with a different year.
      expect(invented.findMatch(second), same(goal));
      invented.upsert(second);
      expect(invented.subGoals, hasLength(1));
    });

    test('a broadening re-ask that drops a year still groups', () {
      // One-directional on purpose: dropping "2024" from a query is a
      // wider version of the same question, not a new instance.
      final ledger = ResearchLedger(objective: 'Vietnam GDP in 2024?');
      final goal = ledger.upsert('Vietnam GDP 2024');

      expect(ledger.findMatch('Vietnam GDP'), same(goal));
    });
  });

  group('ResearchLedger.upsert', () {
    test('creates one entry per genuinely-new query and reuses matches otherwise', () {
      final ledger = ResearchLedger(objective: 'objective');
      final first = ledger.upsert('Vietnam GDP 2024');
      expect(ledger.subGoals, hasLength(1));
      expect(first.searchCount, 1);

      final again = ledger.upsert('vietnam gdp 2024');
      expect(again, same(first));
      expect(ledger.subGoals, hasLength(1));
      expect(first.searchCount, 2);

      ledger.upsert('Thailand GDP 2024');
      expect(ledger.subGoals, hasLength(2));
    });
  });

  group('ResearchLedger.openGap', () {
    test('opens a sub-goal nobody has searched, without billing a search', () {
      final ledger = ResearchLedger(objective: 'objective');
      final gap = ledger.openGap('which college did that player attend');

      expect(ledger.subGoals, hasLength(1));
      expect(gap.status, SubGoalStatus.open);
      // upsert() represents a query actually issued and increments this. A
      // gap is a question nobody has asked yet, so charging it a search
      // would eat the per-sub-goal budget before any search happens.
      expect(gap.searchCount, 0);
      expect(ledger.render(), contains('which college did that player attend'));
    });

    test('reuses an existing sub-goal rather than spawning a lookalike', () {
      final ledger = ResearchLedger(objective: 'objective');
      final searched = ledger.upsert('Jalen Brunson college career');
      final gap = ledger.openGap('Jalen Brunson college');

      expect(gap, same(searched));
      expect(ledger.subGoals, hasLength(1));
      // Reusing must not quietly re-open something already searched, nor
      // bill it a second search.
      expect(searched.searchCount, 1);
    });
  });

  group('ResearchLedger.markSearched', () {
    test('is idempotent — the first evidence wins', () {
      final ledger = ResearchLedger(objective: 'objective');
      final goal = ledger.upsert('Vietnam GDP 2024');

      ledger.markSearched(goal,
          sourceIdStart: 1, sourceIdEnd: 2, excerpt: 'first evidence');
      expect(goal.status, SubGoalStatus.searched);
      expect(goal.sourceIdStart, 1);
      expect(goal.sourceIdEnd, 2);
      expect(goal.excerpt, 'first evidence');

      ledger.markSearched(goal,
          sourceIdStart: 5, sourceIdEnd: 6, excerpt: 'second evidence');
      expect(goal.sourceIdStart, 1);
      expect(goal.sourceIdEnd, 2);
      expect(goal.excerpt, 'first evidence');
    });
  });

  group('ResearchLedger.recordRoundOutcome', () {
    test('tracks two independent stall counters', () {
      final ledger = ResearchLedger(objective: 'objective');
      expect(ledger.roundsSinceProgress, 0);
      expect(ledger.roundsSinceNewSubGoal, 0);

      ledger.recordRoundOutcome(madeProgress: false, openedNewSubGoal: false);
      expect(ledger.roundsSinceProgress, 1);
      expect(ledger.roundsSinceNewSubGoal, 1);

      ledger.recordRoundOutcome(madeProgress: true, openedNewSubGoal: false);
      expect(ledger.roundsSinceProgress, 0);
      expect(ledger.roundsSinceNewSubGoal, 2);

      ledger.recordRoundOutcome(madeProgress: false, openedNewSubGoal: true);
      expect(ledger.roundsSinceProgress, 1);
      expect(ledger.roundsSinceNewSubGoal, 0);
    });
  });

  group('ResearchLedger.render', () {
    test('is empty when no sub-goals exist', () {
      final ledger = ResearchLedger(objective: 'objective');
      expect(ledger.render(), '');
    });

    test('renders the objective, searched entries with source ids and excerpt, and open entries', () {
      final ledger = ResearchLedger(objective: 'find the GDP and tourism trend');
      final searchedGoal = ledger.upsert('Vietnam GDP 2024');
      ledger.markSearched(searchedGoal,
          sourceIdStart: 1, sourceIdEnd: 2, excerpt: 'GDP grew 5% in 2024');
      ledger.upsert('Thailand tourism recovery 2024');

      final rendered = ledger.render();

      expect(rendered, contains('find the GDP and tourism trend'));
      expect(rendered, contains('[1]'));
      expect(rendered, contains('[2]'));
      expect(rendered, contains('GDP grew 5% in 2024'));
      expect(rendered, contains('Still open:'));
      expect(rendered, contains('Thailand tourism recovery 2024'));
      // The harness never claims a searched sub-goal was actually answered.
      expect(rendered, isNot(contains('established')));
    });
  });

  group('selectSupportingExcerpt', () {
    test('returns a candidate verbatim, preferring one that overlaps the topic', () {
      final result = selectSupportingExcerpt(
        [
          'unrelated text about pasta recipes',
          'Vietnam GDP grew due to strong exports in 2024',
          '',
        ],
        'Vietnam GDP 2024',
      );
      expect(result, 'Vietnam GDP grew due to strong exports in 2024');
    });

    test('returns null when every candidate is empty or blank', () {
      expect(selectSupportingExcerpt(['', '   '], 'anything'), isNull);
      expect(selectSupportingExcerpt([], 'anything'), isNull);
    });
  });
}
