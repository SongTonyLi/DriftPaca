import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Utils/text_similarity.dart';

void main() {
  group('trigramJaccard', () {
    test('scores measured near-duplicate query pairs at or above 0.55', () {
      // Measured from a real multi-round Ollama Cloud tool-calling run
      // (gpt-oss:120b): rounds 3/4 re-asked the same population question a
      // year apart, rounds 2/7 re-asked the same medal-count question.
      expect(
        trigramJaccard(
          'Washington D.C. population 2026 estimate',
          'Washington, D.C. population 2025',
        ),
        greaterThanOrEqualTo(0.55),
      );
      expect(
        trigramJaccard(
          'Paris 2024 Summer Olympics gold medals USA count',
          'Paris 2024 Olympic gold medal count USA',
        ),
        greaterThanOrEqualTo(0.55),
      );
    });

    test('scores unrelated queries below 0.55', () {
      expect(
        trigramJaccard(
          'Washington DC population 2025',
          'Washington DC median income 2025',
        ),
        lessThan(0.55),
      );
      expect(
        trigramJaccard('Vietnam GDP 2024', 'Thailand GDP 2024'),
        lessThan(0.55),
      );
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
