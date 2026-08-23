import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Services/web_search_service.dart';
import 'package:llamaseek/Utils/text_splitter.dart';

/// Measured page sizes, uncompressed, as `response.bodyBytes` would hold
/// them. Taken by fetching each URL with the same User-Agent the service
/// sends. Six of eight popular reference pages exceeded the old 1 MB
/// ceiling; these are the ones that matter for the failure that motivated
/// this fix — a three-hop question whose last hop was "which college did
/// Jalen Brunson attend", answerable only from his Wikipedia page.
const _measuredPageSizes = <String, int>{
  'en.wikipedia.org/wiki/Jalen_Brunson': 1462709,
  'en.wikipedia.org/wiki/New_York_Knicks': 1588516,
  'en.wikipedia.org/wiki/Vietnam': 2516643,
  'en.wikipedia.org/wiki/Villanova_Wildcats_mens_basketball': 739677,
};

void main() {
  group('response size ceiling', () {
    test('keeps the reference pages the old 1 MB ceiling silently dropped',
        () {
      for (final entry in _measuredPageSizes.entries) {
        expect(
          WebSearchService.isBodyTooLarge(entry.value),
          isFalse,
          reason: '${entry.key} (${entry.value} B) must be extracted, not '
              'reduced to a title-and-snippet stub that still burns a '
              'source id',
        );
      }
    });

    test('still refuses a pathological body', () {
      expect(WebSearchService.isBodyTooLarge(64 * 1024 * 1024), isTrue);
    });
  });

  group('extracted text ceiling', () {
    test('keeps enough text for chunk selection to reach mid-article', () {
      // The fact that answered the motivating question sits ~1.4% into
      // Brunson's page — about 1,824 chars of 130,272 extracted. That is
      // past the old 8,000-char ceiling only because the top of a Wikipedia
      // page is navigation chrome, which is exactly why truncating BEFORE
      // chunking starves the ranker: it only ever gets to rank chrome.
      final article = 'nav chrome. ' * 900 + // ~10,800 chars of preamble
          'Brunson played college basketball for the Villanova Wildcats. ' +
          'tail. ' * 2000;

      final kept = WebSearchService.truncatePageContent(article);
      expect(kept, contains('Villanova'),
          reason: 'truncating before chunking deletes the answer outright');

      // And once kept, the chunk containing it must be selectable.
      final chunks = splitText(kept, chunkSize: 1500, overlap: 200);
      expect(chunks.any((c) => c.contains('Villanova')), isTrue);
    });

    test('still bounds a pathologically long extraction', () {
      final huge = 'x' * (5 * 1000 * 1000);
      expect(WebSearchService.truncatePageContent(huge).length,
          lessThan(huge.length));
    });
  });
}
