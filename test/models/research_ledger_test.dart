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

  group('ResearchLedger.recordEvidence', () {
    test('accumulates a second search\'s ids instead of discarding them', () {
      // The dropped block is not hypothetical: a query close enough to
      // group onto an existing sub-goal but not close enough to be refused
      // runs for real and consumes ids. Under first-write-wins those ids
      // vanished from the ledger — the panel showed …17-24 then 33-40, and
      // the run under-reported its own searches.
      final ledger = ResearchLedger(objective: 'objective');
      final goal = ledger.upsert('Vietnam GDP 2024');

      ledger.recordEvidence(goal,
          sourceIdStart: 1, sourceIdEnd: 2, excerpt: 'first evidence');
      expect(goal.status, SubGoalStatus.searched);

      ledger.recordEvidence(goal,
          sourceIdStart: 5, sourceIdEnd: 6, excerpt: 'second evidence');

      expect(goal.ranges,
          [const SourceIdRange(1, 2), const SourceIdRange(5, 6)]);
      // The opening evidence still identifies the sub-goal...
      expect(goal.sourceIdStart, 1);
      expect(goal.sourceIdEnd, 2);
      // ...and the excerpt is still the first one, since there is no reason
      // to prefer a later search's illustrative quote.
      expect(goal.excerpt, 'first evidence');
    });

    test('never records the same range twice', () {
      final ledger = ResearchLedger(objective: 'objective');
      final goal = ledger.upsert('Vietnam GDP 2024');

      ledger.recordEvidence(goal, sourceIdStart: 1, sourceIdEnd: 2);
      ledger.recordEvidence(goal, sourceIdStart: 1, sourceIdEnd: 2);

      expect(goal.ranges, hasLength(1));
    });

    test('takes the first non-empty excerpt, not merely the first call', () {
      final ledger = ResearchLedger(objective: 'objective');
      final goal = ledger.upsert('Vietnam GDP 2024');

      ledger.recordEvidence(goal, sourceIdStart: 1, sourceIdEnd: 2);
      ledger.recordEvidence(goal,
          sourceIdStart: 5, sourceIdEnd: 6, excerpt: 'late evidence');

      expect(goal.excerpt, 'late evidence');
    });
  });

  group('ResearchLedger.recordRoundOutcome', () {
    test('tracks two independent stall counters', () {
      final ledger = ResearchLedger(objective: 'objective');
      expect(ledger.roundsSinceProgress, 0);
      expect(ledger.roundsSinceCoverageGrew, 0);

      ledger.recordRoundOutcome(madeProgress: false, broadenedCoverage: false);
      expect(ledger.roundsSinceProgress, 1);
      expect(ledger.roundsSinceCoverageGrew, 1);

      ledger.recordRoundOutcome(madeProgress: true, broadenedCoverage: false);
      expect(ledger.roundsSinceProgress, 0);
      expect(ledger.roundsSinceCoverageGrew, 2);

      ledger.recordRoundOutcome(madeProgress: false, broadenedCoverage: true);
      expect(ledger.roundsSinceProgress, 1);
      expect(ledger.roundsSinceCoverageGrew, 0);
    });
  });

  group('ResearchLedger.searchedSubGoalCount', () {
    test('counts sub-goals with evidence, however many searches produced it', () {
      final ledger = ResearchLedger(objective: 'objective');
      final searched = ledger.upsert('Vietnam GDP 2024');
      ledger.upsert('Thailand tourism recovery 2024');
      expect(ledger.searchedSubGoalCount, 0);

      ledger.recordEvidence(searched, sourceIdStart: 1, sourceIdEnd: 2);
      expect(ledger.searchedSubGoalCount, 1);

      ledger.recordEvidence(searched, sourceIdStart: 9, sourceIdEnd: 10);
      expect(ledger.searchedSubGoalCount, 1);
    });
  });

  group('ResearchLedger.render', () {
    test('is empty when no sub-goals exist', () {
      final ledger = ResearchLedger(objective: 'objective');
      expect(ledger.render(), '');
    });

    test('renders the goal, a ticked checklist with source ids and excerpt, and unticked items', () {
      final ledger = ResearchLedger(objective: 'find the GDP and tourism trend');
      final searchedGoal = ledger.upsert('Vietnam GDP 2024');
      ledger.recordEvidence(searchedGoal,
          sourceIdStart: 1, sourceIdEnd: 2, excerpt: 'GDP grew 5% in 2024');
      ledger.upsert('Thailand tourism recovery 2024');

      final rendered = ledger.render();

      expect(rendered, contains('Goal: find the GDP and tourism trend'));
      expect(rendered, contains('- [x] "Vietnam GDP 2024"'));
      expect(rendered, contains('[1]'));
      expect(rendered, contains('[2]'));
      expect(rendered, contains('GDP grew 5% in 2024'));
      expect(rendered, contains('- [ ] "Thailand tourism recovery 2024"'));
      // The finish line has to be written down, or the model re-decides
      // "am I done?" from scratch every round and keeps saying no.
      expect(rendered, contains(ResearchLedger.stoppingRule));
      // The harness never claims a searched sub-goal was actually answered.
      expect(rendered, isNot(contains('established')));
    });

    test('lists every range a re-searched sub-goal gathered', () {
      final ledger = ResearchLedger(objective: 'objective');
      final goal = ledger.upsert('TikTok new grad offer timing');
      ledger.recordEvidence(goal, sourceIdStart: 1, sourceIdEnd: 8);
      ledger.recordEvidence(goal, sourceIdStart: 25, sourceIdEnd: 32);

      final rendered = ledger.render();

      expect(rendered, contains('16 sources'));
      expect(rendered, contains('[1][2][3][4][5][6][7][8]'));
      expect(rendered, contains('[25][26][27][28][29][30][31][32]'));
      // Merging into one span would claim ids 9-24, which belong to other
      // sub-goals entirely.
      expect(rendered, isNot(contains('[9]')));
    });

    test('renderBrief states the goal and stopping rule before any sub-goal exists', () {
      // This is what reaches the model on the FIRST turn, where there is no
      // transcript for the ledger to ride along on — and the first turn is
      // the one that decides how much research the run does.
      final ledger = ResearchLedger(objective: 'when does TikTok start '
          'new-grad offer negotiations');

      final brief = ledger.renderBrief();

      expect(brief, contains('Goal: when does TikTok start'));
      expect(brief, contains(ResearchLedger.stoppingRule));
      expect(brief, isNot(contains('Checklist')));
    });
  });

  group('ResearchLedger.userQuestion', () {
    test('splits instances the user named even when the goal paraphrases them away', () {
      // The derived goal is a model's restatement and may drop the years.
      // The instance split has to keep working off what the user actually
      // typed, or a four-year question collapses to one sub-goal again.
      final ledger = ResearchLedger(
        objective: 'find recent US inflation rates',
        userQuestion: 'US inflation rate in 2023 and 2024?',
      );
      ledger.upsert('US inflation rate 2023');

      expect(ledger.findMatch('US inflation rate 2024'), isNull);
    });

    test('defaults to the objective when no separate question is given', () {
      final ledger = ResearchLedger(objective: 'US inflation in 2023 and 2024');
      expect(ledger.userQuestion, 'US inflation in 2023 and 2024');
      ledger.upsert('US inflation rate 2023');
      expect(ledger.findMatch('US inflation rate 2024'), isNull);
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
