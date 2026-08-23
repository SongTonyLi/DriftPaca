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
