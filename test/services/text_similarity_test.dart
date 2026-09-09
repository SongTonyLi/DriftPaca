import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/research_ledger.dart';
import 'package:llamaseek/Utils/text_similarity.dart';

void main() {
  group('trigramJaccard', () {
    // Every query below is a VERBATIM query emitted by gpt-oss:120b during a
    // real multi-round run: it re-asked the same population question three
    // ways and the same medal-count question four ways, and the old
    // exact-match normalisation caught none of them. These pairs are the
    // reason this function exists, so they are asserted against the
    // threshold the ledger actually groups on — not an arbitrary constant.
    const nearDuplicates = <List<String>>[
      [
        'Washington D.C. population 2026 estimate',
        'Washington, D.C. population 2025'
      ],
      [
        'Washington D.C. population 2026 estimate',
        'Washington DC population 2026'
      ],
      ['Washington, D.C. population 2025', 'Washington DC population 2026'],
      [
        '2024 Summer Olympics medal table gold medals United States 39',
        '2024 Paris Olympics gold medals United States 39'
      ],
      [
        'Paris 2024 Summer Olympics gold medals USA count',
        'Paris 2024 Olympic gold medal count USA'
      ],
    ];

    test('groups every measured near-duplicate pair onto one sub-goal', () {
      for (final pair in nearDuplicates) {
        final ledger = ResearchLedger(objective: 'irrelevant');
        final first = ledger.upsert(pair[0]);
        final second = ledger.upsert(pair[1]);
        expect(
          identical(first, second),
          isTrue,
          reason: 'expected "${pair[1]}" to group onto "${pair[0]}" '
              '(score ${trigramJaccard(pair[0], pair[1]).toStringAsFixed(3)})',
        );
        expect(ledger.subGoals, hasLength(1));
      }
    });

    test('keeps genuinely different questions as separate sub-goals', () {
      const distinct = <List<String>>[
        // Negative controls spanning the same run: a different question
        // about the same city, and two unrelated topics.
        [
          'Washington DC population 2025',
          'Washington DC median income 2025'
        ],
        ['Vietnam GDP 2024', 'Thailand GDP 2024'],
        [
          'Washington D.C. population 2026 estimate',
          '2024 Summer Olympics most gold medals which country'
        ],
      ];
      for (final pair in distinct) {
        final ledger = ResearchLedger(objective: 'irrelevant');
        ledger.upsert(pair[0]);
        ledger.upsert(pair[1]);
        expect(
          ledger.subGoals,
          hasLength(2),
          reason: 'expected "${pair[0]}" and "${pair[1]}" to stay separate '
              '(score ${trigramJaccard(pair[0], pair[1]).toStringAsFixed(3)})',
        );
      }
    });

    // The normalizer used to collapse every non-ASCII character to a space,
    // so ANY pure-CJK query normalized to the empty string. Two completely
    // unrelated Chinese questions therefore scored 1.0, the ledger grouped
    // every one of them onto a single sub-goal, and _isLedgerBlocked
    // refused every search after the first — a Chinese user got exactly one
    // search per turn, forever, with the ledger reporting one sub-goal.
    test('keeps unrelated non-Latin queries apart', () {
      const unrelated = <List<String>>[
        ['越南目前的人口是多少', '法国的首都是哪座城市'],
        ['苹果公司的首席执行官是谁', '珠穆朗玛峰有多高'],
        ['東京の人口', '大阪の天気'],
        ['ما هو عدد سكان فيتنام', 'ما هي عاصمة فرنسا'],
      ];
      for (final pair in unrelated) {
        final score = trigramJaccard(pair[0], pair[1]);
        expect(score, lessThan(0.40),
            reason: '"${pair[0]}" vs "${pair[1]}" scored '
                '${score.toStringAsFixed(3)} — at or above the ledger\'s '
                'grouping threshold these become one sub-goal');

        final ledger = ResearchLedger(objective: 'irrelevant');
        ledger.upsert(pair[0]);
        ledger.upsert(pair[1]);
        expect(ledger.subGoals, hasLength(2));
      }
    });

    test('still groups genuine near-duplicates in a non-Latin script', () {
      // The mechanism has to keep working, not just stop over-firing.
      final ledger = ResearchLedger(objective: 'irrelevant');
      final first = ledger.upsert('越南目前的人口是多少');
      final second = ledger.upsert('越南目前的人口是多少人');
      expect(identical(first, second), isTrue,
          reason: 'score '
              '${trigramJaccard('越南目前的人口是多少', '越南目前的人口是多少人').toStringAsFixed(3)}');
    });

    test('a mixed-script query is not mistaken for a pure-script one', () {
      // "2026" alone used to be all that survived normalization here, so a
      // CJK question containing a year compared as if it were just that year.
      expect(trigramJaccard('2026年世界杯冠军是哪个国家', '2026年奥运会金牌最多的国家'),
          lessThan(0.75));
    });

    test('is symmetric and 1.0 for identical strings modulo case/whitespace', () {
      expect(trigramJaccard('Vietnam GDP', 'vietnam   gdp'), 1.0);
      expect(
        trigramJaccard('a b', 'c d'),
        trigramJaccard('c d', 'a b'),
      );
    });
  });

  group('properNounTokens', () {
    // The user side of ResearchLedger's instance check. It answers one
    // question — "which things did the user NAME?" — and it has to answer
    // it conservatively, because a wrong "yes" splits one question into a
    // sub-goal per rewording, and each of those carries a fresh search
    // budget and a round that looks like it broadened coverage.
    test('reads the names out of a question that lists several', () {
      expect(
        properNounTokens('What is the current population of Tokyo, Delhi, '
            'Shanghai and São Paulo? Give the figure for each.'),
        {'tokyo', 'delhi', 'shanghai', 'são', 'paulo'},
        reason: 'four names the user typed; a multi-word name contributes '
            'each of its own tokens, because the query side matches token '
            'by token and a model may write only half of one',
      );
      expect(properNounTokens('Compare NASA and ESA budgets.'),
          {'nasa', 'esa'},
          reason: 'the sentence-initial verb names nothing, and the '
              'lowercase noun after ESA ends its run');
    });

    test('reads nothing out of a question with a single subject', () {
      // One capitalised phrase is what the question is ABOUT. Splitting on
      // it would fragment one question, so a single run yields nothing —
      // and adjacent capitalised words are one run, which is what makes
      // "Vietnam GDP" and "Mount Everest" single subjects rather than two
      // names apiece.
      for (final single in [
        'What is Vietnam GDP?',
        'How is Apple doing this quarter?',
        "What was Vietnam's GDP in 2024?",
        'How tall is Mount Everest?',
        'What is the outlook for Brazilian inflation?',
        'How many people live in the Tokyo metropolitan area as of 2025?',
      ]) {
        expect(properNounTokens(single), isEmpty,
            reason: '"$single" names one thing, so capitalisation carries no '
                'instance signal and every re-ask of it must still group');
      }
    });

    test('reads nothing out of a Title Case or shouted question', () {
      // Run-merging is what collapses these to a single run. Without it, a
      // user who types in title case or in caps would have every word of
      // their question treated as an instance they named.
      expect(
          properNounTokens(
              'What Is The Current Population Of Tokyo And Delhi?'),
          isEmpty);
      expect(
          properNounTokens(
              'WHAT IS THE CURRENT POPULATION OF TOKYO AND DELHI?'),
          isEmpty);
    });

    test('reads nothing out of an uncased script', () {
      // No character in these is uppercase, so the name split cannot fire
      // for a Chinese, Japanese, Arabic, Hebrew or Thai question at all —
      // by construction, not by a script list that could go stale. Those
      // runs keep exactly the grouping trigramJaccard gives them.
      for (final uncased in [
        '东京和德里目前的人口分别是多少？',
        '東京と大阪の人口は？',
        'ما هو عدد سكان فيتنام وفرنسا',
        'ประชากรของโตเกียวและเดลี',
      ]) {
        expect(properNounTokens(uncased), isEmpty, reason: uncased);
      }
    });

    test('is empty for text with nothing capitalised to read', () {
      expect(properNounTokens(''), isEmpty);
      expect(properNounTokens('irrelevant'), isEmpty);
      expect(properNounTokens('what is the population of tokyo and delhi'),
          isEmpty,
          reason: 'an all-lowercase question names nothing this can see, so '
              'it groups exactly as it did before');
    });
  });

  group('properNounTokensInChoices', () {
    // The same question — "which things did the user NAME?" — asked of
    // clarification options they TICKED rather than of a question they
    // typed. Both safety rules carry over; only the sentence-initial skip
    // does not, because an option is a label rather than a sentence.
    test('reads the names out of the options the user ticked', () {
      expect(properNounTokensInChoices(const ['Tokyo', 'Delhi']),
          {'tokyo', 'delhi'},
          reason: 'a one-word option is a name, not a sentence opener — '
              'dropping its first word the way a typed question\'s is '
              'dropped would leave two ticked cities naming nothing, and '
              'collapse them onto one sub-goal');
      expect(properNounTokensInChoices(const ['São Paulo', 'Tokyo']),
          {'são', 'paulo', 'tokyo'},
          reason: 'adjacent capitalised words are still one name, and it '
              'still contributes each of its own tokens');
      expect(properNounTokensInChoices(const ['Tokyo, Delhi']),
          {'tokyo', 'delhi'},
          reason: 'and a segment boundary still ends a run, so one option '
              'naming two things is two names');
    });

    test('reads nothing out of a single ticked option', () {
      // The rule that keeps this from over-firing: one name is what the
      // run is ABOUT. Splitting on it would fragment one question into a
      // sub-goal per rewording, each with a fresh search budget.
      expect(properNounTokensInChoices(const ['Tokyo']), isEmpty);
      expect(
          properNounTokensInChoices(
              const ['The Phoenix Mercury basketball team']),
          isEmpty,
          reason: 'a multi-word option is still one run, so ticking it alone '
              'names nothing');
      expect(properNounTokensInChoices(const []), isEmpty);
    });

    test('digits are left to numericTokens', () {
      expect(properNounTokensInChoices(const ['2023', '2024']), isEmpty,
          reason: 'nothing in a bare year is capitalised; the ledger reads '
              'those through numericTokens, which has no two-of-them rule');
      expect(properNounTokensInChoices(const ['Q1 2025', 'Q4 2024']),
          {'q1', 'q4'},
          reason: 'a quarter label carries both kinds at once, and reading '
              'the capitalised half here costs nothing: the digits already '
              'split these two apart');
    });

    test('an option opening with a capitalised article offers that word too',
        () {
      // The accepted residual of not skipping an option's first word,
      // pinned so it is a known trade-off rather than a surprise. It takes
      // TWO ticked options to reach the two-names bar at all, and the
      // alternative loses every one-word option — which is what this
      // function exists for.
      expect(
          properNounTokensInChoices(
              const ['The planet Mercury', 'The Phoenix Mercury team']),
          contains('the'),
          reason: 'a ticked string is the user\'s own explicit choice, read '
              'as they endorsed it — incidental words and all, exactly as a '
              'picked option\'s incidental digits are kept');
    });
  });

  group('wordTokens', () {
    test('normalizes the query side exactly as the user side is normalized', () {
      // Both sides of the instance comparison run through one tokenizer on
      // purpose: if the user's "Vietnam's" kept its apostrophe while a
      // model's "vietnams" did not, the two would never match and the
      // split would silently stop firing.
      expect(wordTokens("Vietnam's GDP in D.C. 2024"),
          {'vietnams', 'gdp', 'in', 'dc', '2024'},
          reason: 'apostrophes and periods are stripped inside a word, '
              'digits are kept as tokens of their own, and everything is '
              'lowercased');
      expect(wordTokens('current population of São Paulo'),
          {'current', 'population', 'of', 'são', 'paulo'},
          reason: 'case-blind on the query side: a model writes the city '
              'name however it likes');
      expect(wordTokens('Tokyo, Delhi — Shanghai; (São Paulo)'),
          {'tokyo', 'delhi', 'shanghai', 'são', 'paulo'},
          reason: 'punctuation separates tokens rather than joining them');
    });
  });

  group('queryCoverage', () {
    test('scores a short query higher against a chunk containing its terms', () {
      const query = 'Vietnam GDP 2024';
      const withTerms =
          "Vietnam's GDP in 2024 grew significantly according to reports, "
          'with strong export numbers across many sectors of the economy '
          'driving overall growth this year and beyond.';
      const withoutTerms =
          'The weather today in Hanoi is sunny with a high of 30 degrees '
          'celsius and light winds from the northeast, typical for this '
          'time of year in the region.';

      final withScore = queryCoverage(query, withTerms);
      final withoutScore = queryCoverage(query, withoutTerms);

      expect(withScore, greaterThan(withoutScore));
      expect(withScore, greaterThan(0.5));
      expect(withoutScore, 0.0);
    });
  });
}
