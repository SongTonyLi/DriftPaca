import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/search_event.dart';
import 'package:llamaseek/Utils/search_thinking_utils.dart';

void main() {
  group('encodeSearchSegments / decodeSearchSegments', () {
    test('roundtrips thinking segments', () {
      final segments = <MessageSegment>[
        ThinkingSegment('Planning reasoning...'),
      ];
      final encoded = encodeSearchSegments(segments);
      expect(encoded, startsWith('<!--SEARCH_DATA:'));
      expect(encoded, contains('-->'));

      final decoded = decodeSearchSegments(encoded);
      expect(decoded, isNotNull);
      expect(decoded!.length, 1);
      expect(decoded[0], isA<ThinkingSegment>());
      expect((decoded[0] as ThinkingSegment).text, 'Planning reasoning...');
    });

    test('roundtrips search card segments with content', () {
      final segments = <MessageSegment>[
        ThinkingSegment('Need to find GDP data'),
        SearchCardSegment(
          query: 'Vietnam GDP 2025',
          urls: [
            SearchURLStatus(
                url: 'https://imf.org/data',
                domain: 'imf.org',
                state: SearchURLState.success),
            SearchURLStatus(
                url: 'https://google.com',
                domain: 'google.com',
                state: SearchURLState.failed),
          ],
          resultCount: 5,
          isComplete: true,
          extractedContent: 'Vietnam GDP projected at 6.5% growth...',
        ),
      ];

      final encoded = encodeSearchSegments(segments);
      final decoded = decodeSearchSegments(encoded);

      expect(decoded, isNotNull);
      expect(decoded!.length, 2);

      final card = decoded[1] as SearchCardSegment;
      expect(card.query, 'Vietnam GDP 2025');
      expect(card.urls.length, 2);
      expect(card.urls[0].domain, 'imf.org');
      expect(card.urls[0].state, SearchURLState.success);
      expect(card.urls[1].state, SearchURLState.failed);
      expect(card.resultCount, 5);
      expect(card.extractedContent, contains('6.5%'));
      expect(card.isComplete, true);
    });

    test('returns null for non-search thinking', () {
      final result = decodeSearchSegments('Regular thinking text');
      expect(result, isNull);
    });

    test('returns null for empty string', () {
      final result = decodeSearchSegments('');
      expect(result, isNull);
    });

    test('handles malformed base64 gracefully', () {
      final result = decodeSearchSegments('<!--SEARCH_DATA:!!!invalid!!!-->');
      expect(result, isNull);
    });
  });

  group('stripSearchData', () {
    test('strips header from thinking text', () {
      final encoded = encodeSearchSegments([ThinkingSegment('test')]);
      final combined = '${encoded}Human readable text';
      final stripped = stripSearchData(combined);
      expect(stripped, 'Human readable text');
      expect(stripped, isNot(contains('SEARCH_DATA')));
    });

    test('returns unchanged if no header', () {
      expect(stripSearchData('Just text'), 'Just text');
    });
  });

  group('mergeSearchThinking', () {
    test('merges both parts', () {
      final result = mergeSearchThinking(
          searchThinking: 'search', modelThinking: 'model');
      expect(result, contains('search'));
      expect(result, contains('model'));
      expect(result, contains('---'));
    });

    test('returns model thinking if search empty', () {
      final result =
          mergeSearchThinking(searchThinking: '', modelThinking: 'model');
      expect(result, 'model');
    });

    test('returns search thinking if model empty', () {
      final result =
          mergeSearchThinking(searchThinking: 'search', modelThinking: '');
      expect(result, 'search');
    });
  });

  group('modelThinkingFromCombined', () {
    test('extracts model portion', () {
      final combined = mergeSearchThinking(
          searchThinking: 'search part', modelThinking: 'model part');
      expect(modelThinkingFromCombined(combined), 'model part');
    });

    test('returns full text if no separator', () {
      expect(modelThinkingFromCombined('no separator'), 'no separator');
    });

    test('handles search data header', () {
      final encoded = encodeSearchSegments([ThinkingSegment('test')]);
      final combined = '${encoded}search text\n\n---\n\nmodel text';
      expect(modelThinkingFromCombined(combined), 'model text');
    });
  });
}
