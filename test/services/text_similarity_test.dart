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
