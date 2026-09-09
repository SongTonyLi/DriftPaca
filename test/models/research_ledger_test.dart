import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/research_ledger.dart';
import 'package:llamaseek/Utils/text_similarity.dart';

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
      // Reusing must not bill a second search...
      expect(searched.searchCount, 1);
      // ...and must still record the gap, or the checklist goes on implying
      // coverage the completeness gate has just rejected.
      expect(searched.outstandingGaps, ['Jalen Brunson college']);
    });
  });

  group('ResearchLedger.openGap on a searched sub-goal', () {
    /// A sub-goal searched once, with three sources filed against it — the
    /// shape every gate gap lands on when its wording groups (>= 0.40
    /// trigram) onto ground the run has already covered.
    ResearchLedger seeded() {
      final ledger = ResearchLedger(objective: 'find the GDP');
      final goal = ledger.upsert('Vietnam GDP 2024');
      ledger.recordEvidence(goal,
          sourceIdStart: 1, sourceIdEnd: 3, excerpt: 'GDP grew 5%');
      return ledger;
    }

    test('files the gap on the sub-goal and renders one unticked line for it',
        () {
      final ledger = seeded();
      final goal = ledger.subGoals.single;

      final filed = ledger.openGap('Vietnam GDP 2024 in US dollars');

      expect(filed, same(goal), reason: 'no lookalike is spawned beside it');
      expect(goal.outstandingGaps, ['Vietnam GDP 2024 in US dollars']);
      // Everything the earlier search established is untouched: the gate
      // rejected the ANSWER's coverage, not the sources.
      expect(goal.searchCount, 1);
      expect(goal.status, SubGoalStatus.searched);
      expect(goal.ranges, [const SourceIdRange(1, 3)]);
      expect(goal.excerpt, 'GDP grew 5%');

      final rendered = ledger.render();
      expect(rendered, contains('- [ ] "Vietnam GDP 2024 in US dollars"'));
      expect(rendered, contains('search for it specifically'));
      expect(rendered, isNot(contains('- [x]')),
          reason: 'nothing may claim this ground is covered while the gate '
              'says it is not');
      // The evidence is still cited, because the gap notice riding in the
      // same request tells the model to keep what it already established.
      expect(rendered, contains('Searching "Vietnam GDP 2024" already '
          'returned 3 sources, see [1][2][3]'));
      expect(rendered, isNot(contains('GDP grew 5%')),
          reason: 'the excerpt is scraped page text, and the one line the '
              'model is being told to act on is the last place to re-inject '
              'a chunk of somebody\'s web page');
    });

    test('the closed brief states the gap without ordering a search', () {
      final ledger = seeded();
      ledger.openGap('Vietnam GDP 2024 in US dollars');

      final brief = ledger.renderBrief(closed: true);

      expect(brief, contains('- [ ] "Vietnam GDP 2024 in US dollars"'));
      expect(brief, isNot(contains('search for it specifically')),
          reason: 'on a request that carries no tool, ordering a search is '
              'exactly the contradiction ResearchLedger.closedRule exists to '
              'remove');
      expect(brief, contains('say plainly in the answer that this part is '
          'unverified'));
    });

    test('a reopened sub-goal stops counting as covered ground until '
        'evidence lands', () {
      final ledger = seeded();
      expect(ledger.searchedSubGoalCount, 1);

      final goal = ledger.openGap('Vietnam GDP 2024 in US dollars');
      expect(ledger.searchedSubGoalCount, 0,
          reason: 'otherwise the one corrective round the harness itself '
              'demanded registers as covering nothing new, and the run that '
              'obeyed the gate is reported as unproductiveRounds');

      ledger.recordEvidence(goal, sourceIdStart: 9, sourceIdEnd: 10);
      expect(ledger.searchedSubGoalCount, 1);
    });

    test('recordEvidence closes every outstanding gap and the item ticks '
        'again', () {
      final ledger = seeded();
      final goal = ledger.openGap('Vietnam GDP 2024 in US dollars');
      ledger.openGap('Vietnam GDP 2024 growth rate');
      expect(goal.outstandingGaps, hasLength(2));

      ledger.recordEvidence(goal, sourceIdStart: 9, sourceIdEnd: 10);

      expect(goal.outstandingGaps, isEmpty);
      final rendered = ledger.render();
      expect(rendered, contains('- [x] "Vietnam GDP 2024"'));
      expect(rendered, contains('5 sources'),
          reason: 'and the reopening cost none of the accumulated evidence');
    });

    test('two gaps on one sub-goal are both quoted, and a repeat is deduped',
        () {
      final ledger = seeded();
      final goal = ledger.openGap('Vietnam GDP 2024 in US dollars');
      ledger.openGap('Vietnam GDP 2024 growth rate');
      ledger.openGap('vietnam  GDP 2024 IN US dollars');

      expect(goal.outstandingGaps, [
        'Vietnam GDP 2024 in US dollars',
        'Vietnam GDP 2024 growth rate',
      ], reason: 'a list, not an overwrite — the gate may report up to '
          'maxCoverageGaps parts of one question — and deduped on the same '
          'normalization findMatch uses');
      final rendered = ledger.render();
      expect(rendered, contains('"Vietnam GDP 2024 in US dollars" / '
          '"Vietnam GDP 2024 growth rate"'));
    });

    test('a gap worded exactly like the sub-goal\'s query is still filed', () {
      // This is precisely the case SearchAgent._isLedgerBlocked's
      // exact-repeat test would otherwise refuse: skipping it here would
      // leave the harness ordering a search it then rejects as a byte-for-
      // byte duplicate.
      final ledger = seeded();
      final goal = ledger.openGap('Vietnam GDP 2024');

      expect(goal.outstandingGaps, ['Vietnam GDP 2024']);
      expect(ledger.render(), contains('- [ ] "Vietnam GDP 2024"'));
    });

    test('a gap landing on a never-searched sub-goal files nothing', () {
      // The pre-seeded checklist shape: SearchAgent.run opens every
      // ResearchGoal.subQuestion through openGap before any search exists,
      // and none of them may start claiming the drafted answer missed
      // something when there is no draft yet.
      final ledger = ResearchLedger(objective: 'find the GDP');
      ledger.openGap('Vietnam GDP 2024');
      final again = ledger.openGap('Vietnam GDP 2024 figures');

      expect(ledger.subGoals, hasLength(1));
      expect(again.outstandingGaps, isEmpty);
      expect(again.searchCount, 0);
      expect(ledger.render(), contains('- [ ] "Vietnam GDP 2024"'));
      expect(ledger.render(), isNot(contains('drafted answer')));
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

  group('ResearchLedger closed brief', () {
    test('swaps the stopping rule for the closed rule and keeps the checklist', () {
      final ledger = ResearchLedger(objective: 'find the GDP');
      final goal = ledger.upsert('Vietnam GDP 2024');
      ledger.recordEvidence(goal, sourceIdStart: 1, sourceIdEnd: 2);
      ledger.openGap('Thailand tourism recovery 2024');

      final brief = ledger.renderBrief(closed: true);

      expect(brief, contains('Goal: find the GDP'));
      expect(brief, contains('- [x] "Vietnam GDP 2024"'));
      expect(brief, contains('- [ ] "Thailand tourism recovery 2024"'));
      expect(brief, contains(ResearchLedger.closedRule));
      // The open rule invites a search; on a request carrying no tool that
      // invitation is the contradiction this variant exists to remove.
      expect(brief, isNot(contains(ResearchLedger.stoppingRule)));
      expect(ledger.render(closed: true), brief);
    });

    test('is open by default, so every existing caller is unchanged', () {
      final ledger = ResearchLedger(objective: 'objective');
      ledger.upsert('anything');

      expect(ledger.renderBrief(), contains(ResearchLedger.stoppingRule));
      expect(ledger.render(), contains(ResearchLedger.stoppingRule));
      expect(ledger.render(), isNot(contains(ResearchLedger.closedRule)));
    });
  });

  group('ResearchClarification', () {
    test('the brief carries what the user clarified on every turn', () {
      // The answering model's history holds only the ambiguous original,
      // so the brief is where the user's choice reaches it.
      final ledger = ResearchLedger(
        objective: 'Find the latest Mercury results',
        clarification: ResearchClarification.note(
            'Which Mercury?', ['The Phoenix Mercury basketball team']),
      );

      expect(ledger.renderBrief(),
          contains('The user clarified: Which Mercury? The Phoenix Mercury basketball team'));
      expect(ResearchLedger(objective: 'x').renderBrief(),
          isNot(contains('The user clarified')));
    });

    test('picks folded into the question count as requested instances', () {
      // "Population for which years?" answered with two years is two
      // questions, exactly as if the user had typed both years — so the
      // ledger must keep their searches apart instead of grouping them.
      final question = ResearchClarification.clarifiedQuestion(
          'What was the population of Lagos?',
          'Which years?',
          ['2023', '2024']);
      final ledger = ResearchLedger(
        objective: 'Establish the population of Lagos',
        userQuestion: question,
      );
      ledger.upsert('Lagos population 2023');

      expect(question, startsWith('What was the population of Lagos?'));
      expect(ledger.findMatch('Lagos population 2024'), isNull);
    });

    test('an empty pick list leaves the question untouched', () {
      expect(ResearchClarification.clarifiedQuestion('q', 'which?', const []),
          'q');
      expect(ResearchClarification.note('which?', const []), isEmpty);
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

    // A candidate longer than maxLength is quoted from the window that
    // earned it the win, not from character 0. The old behavior — score the
    // whole candidate, return its opening — is what made the ledger record
    // a reference page's navigation sidebar as evidence for every sub-goal
    // it was cited on (see loopholes/ledger_excerpt_prefers_page_chrome).
    group('windowing a candidate longer than maxLength', () {
      /// ~500 chars of prose that shares no trigrams with the query below,
      /// so the only thing the ranker can be responding to is the final
      /// sentence.
      final offTopicFiller = List.filled(
        7,
        'Sourdough starter needs regular feeding to stay active in a warm '
            'kitchen.',
      ).join(' ');

      const onTopicTail =
          'Vietnam GDP grew 7.1% in 2024, led by electronics exports.';

      test('quotes the on-topic tail and marks the elided head with ...', () {
        final candidate = '$offTopicFiller $onTopicTail';
        expect(candidate.length, greaterThan(220),
            reason: 'the windowing path only runs above maxLength');

        final result = selectSupportingExcerpt([candidate], 'Vietnam GDP 2024');

        expect(result, isNotNull);
        expect(result!, contains(onTopicTail),
            reason: 'the sentence that earned the candidate its score is the '
                'sentence that gets stored');
        expect(result, startsWith('...'),
            reason: 'text before the quoted window was dropped, and the '
                'excerpt says so rather than passing itself off as the '
                'start of the source');
        expect(result, isNot(endsWith('...')),
            reason: 'the window runs to the end of the candidate, so there '
                'is nothing on the right to mark as elided');
      });

      test('falls back to the opening window when no window scores at all',
          () {
        // No trigram of the query appears anywhere in the candidate, so
        // every window ties at 0.0 and the earliest wins — the old
        // head-of-candidate behavior, kept deliberately as the no-signal
        // fallback since one window is then as good as another.
        const query = 'zebra migration corridors';
        final candidate = List.filled(40, 'ppp qqq').join(' ');
        expect(candidate.length, greaterThan(220));
        expect(queryCoverage(query, candidate), 0.0,
            reason: 'the premise has to be checked, not assumed: the whole '
                'candidate is the superset of every window, so zero '
                'coverage here means zero on all of them');

        final result = selectSupportingExcerpt([candidate], query)!;

        expect(result, isNot(startsWith('...')),
            reason: 'the first window is quoted, so nothing was elided on '
                'the left to mark');
        expect(result, endsWith('...'),
            reason: 'but the rest of the candidate was dropped');
        expect(candidate, startsWith(result.substring(0, result.length - 3)),
            reason: 'and what is quoted is the candidate\'s own opening');
      });

      test('the quoted window is verbatim from exactly one candidate, and '
          'never longer than maxLength', () {
        final candidates = <String>[
          List.filled(6, 'Unrelated notes about lighthouse masonry.').join(' '),
          '$offTopicFiller $onTopicTail',
          'short snippet',
        ];

        final result = selectSupportingExcerpt(candidates, 'Vietnam GDP 2024')!;
        final quoted =
            result.replaceAll(RegExp(r'^\.\.\.'), '').replaceAll(RegExp(r'\.\.\.$'), '');

        expect(quoted.length, lessThanOrEqualTo(220),
            reason: 'splitText(chunkSize: 220, overlap: 0) never emits a '
                'window over the cap, so the ledger line stays bounded');
        expect(candidates.where((c) => c.contains(quoted)).length, 1,
            reason: 'the excerpt is a verbatim substring of one candidate — '
                'never stitched together and never invented');
      });
    });
  });
}
