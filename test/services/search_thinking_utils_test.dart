import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/research_ledger.dart';
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

    test('roundtrips a clarification card with what was chosen', () {
      final decoded = decodeSearchSegments(encodeSearchSegments([
        ClarificationSegment(
          question: 'Which Mercury?',
          options: const ['The planet', 'The team'],
          selected: const ['The team'],
        ),
      ]));

      final card = decoded!.single as ClarificationSegment;
      expect(card.question, 'Which Mercury?');
      expect(card.options, ['The planet', 'The team']);
      expect(card.selected, ['The team']);
      expect(card.isAnswered, isTrue);
    });

    test('a card still waiting when saved comes back as skipped', () {
      // A reloaded message has no run to resume, so a card that reads as
      // still asking would be a form wired to nothing.
      final decoded = decodeSearchSegments(encodeSearchSegments([
        ClarificationSegment(question: 'Which?', options: const ['a', 'b']),
      ]));

      final card = decoded!.single as ClarificationSegment;
      expect(card.isAnswered, isTrue);
      expect(card.selected, isEmpty);
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

    test('round-trips a ResearchLedgerSegment and SearchCardSegment.round/skipReason', () {
      final segments = <MessageSegment>[
        SearchCardSegment(
          query: 'Vietnam GDP 2025',
          isComplete: true,
          round: 2,
          skipReason: 'You already asked something very close to this.',
        ),
        ResearchLedgerSegment(
          objective: 'What is Vietnam GDP in 2025?',
          entries: [
            const LedgerEntryView(
              query: 'Vietnam GDP 2025',
              searched: true,
              ranges: [SourceIdRange(1, 3), SourceIdRange(11, 12)],
              excerpt: 'Vietnam GDP projected at 6.5% growth...',
            ),
            const LedgerEntryView(
              query: 'Vietnam GDP forecast 2026',
              searched: false,
            ),
          ],
          terminationReason: 'converged',
        ),
      ];

      final encoded = encodeSearchSegments(segments);
      final decoded = decodeSearchSegments(encoded);

      expect(decoded, isNotNull);
      expect(decoded!.length, 2);

      final card = decoded[0] as SearchCardSegment;
      expect(card.query, 'Vietnam GDP 2025');
      expect(card.round, 2);
      expect(card.skipReason, 'You already asked something very close to this.');

      final ledger = decoded[1] as ResearchLedgerSegment;
      expect(ledger.objective, 'What is Vietnam GDP in 2025?');
      expect(ledger.entries.length, 2);
      expect(ledger.entries[0].query, 'Vietnam GDP 2025');
      expect(ledger.entries[0].searched, isTrue);
      expect(ledger.entries[0].ranges,
          [const SourceIdRange(1, 3), const SourceIdRange(11, 12)]);
      expect(ledger.entries[0].sourceCount, 5);
      expect(ledger.entries[0].excerpt, contains('6.5%'));
      expect(ledger.entries[1].query, 'Vietnam GDP forecast 2026');
      expect(ledger.entries[1].searched, isFalse);
      expect(ledger.entries[1].ranges, isEmpty);
      expect(ledger.terminationReason, 'converged');
    });

    test('decodes a ledger persisted with the single sourceIdStart/End pair', () {
      // Written by every build before a sub-goal could carry evidence from
      // more than one search. Those chats still have to render their chip.
      const legacy =
          '<!--SEARCH_DATA:W3sidHlwZSI6ImxlZGdlciIsIm9iamVjdGl2ZSI6Ik9sZCBnb2FsIiwiZW50cmllcyI6W3sicXVlcnkiOiJvbGQgcXVlcnkiLCJzZWFyY2hlZCI6dHJ1ZSwic291cmNlSWRTdGFydCI6NCwic291cmNlSWRFbmQiOjZ9XX1d-->\n';

      final decoded = decodeSearchSegments(legacy);

      final ledger = decoded!.single as ResearchLedgerSegment;
      expect(ledger.objective, 'Old goal');
      expect(ledger.entries.single.ranges, [const SourceIdRange(4, 6)]);
      expect(ledger.entries.single.sourceCount, 3);
    });

    test('decodes a legacy persisted blob unchanged', () {
      // Hand-built, NOT via encodeSearchSegments, to genuinely simulate a
      // blob written by the pre-ledger/round/skipReason codec.
      final legacyData = [
        {'type': 'thinking', 'text': 'Planning reasoning...'},
        {
          'type': 'search',
          'query': 'Vietnam GDP 2025',
          'urls': [
            {
              'url': 'https://imf.org/data',
              'domain': 'imf.org',
              'title': '',
              'state': 'success',
            },
          ],
          'resultCount': 5,
          'error': null,
          'content': 'Vietnam GDP projected at 6.5% growth...',
        },
      ];
      final json = jsonEncode(legacyData);
      final encodedBody = base64Encode(utf8.encode(json));
      final blob = '<!--SEARCH_DATA:$encodedBody-->\nHuman readable text';

      final decoded = decodeSearchSegments(blob);

      expect(decoded, isNotNull);
      expect(decoded!.length, 2);
      expect(decoded[0], isA<ThinkingSegment>());
      expect((decoded[0] as ThinkingSegment).text, 'Planning reasoning...');

      final card = decoded[1] as SearchCardSegment;
      expect(card.query, 'Vietnam GDP 2025');
      expect(card.resultCount, 5);
      expect(card.extractedContent, contains('6.5%'));
      expect(card.round, isNull);
      expect(card.skipReason, isNull);
      expect(decoded.whereType<ResearchLedgerSegment>(), isEmpty);
    });

    test(
        'a 15-card segment list with per-source content already capped encodes under a fixed size budget',
        () {
      String filler(int length) {
        final buffer = StringBuffer();
        while (buffer.length < length) {
          buffer.write('lorem ipsum dolor sit amet consectetur adipiscing ');
        }
        return buffer.toString().substring(0, length);
      }

      // Mirrors SearchAgent.defaultMaxSearches's worst case: up to 15
      // cards (search_agent.dart), each with up to 8 sources
      // (WebSearchService's default maxResults) whose content is capped at
      // ChatPageViewModel's _maxPersistedSourceChars (2000) rather than the
      // raw, untruncated ~3000-char (2 chunks x 1500) text a real search
      // round produces before that cap is applied — and with no
      // extractedContent, since sources[] alone now carries this text.
      final segments = <MessageSegment>[
        for (var card = 0; card < 15; card++)
          SearchCardSegment(
            query: 'query number $card',
            isComplete: true,
            round: card + 1,
            resultCount: 8,
            urls: [
              for (var s = 0; s < 8; s++)
                SearchURLStatus(
                  url: 'https://example$card.com/page$s',
                  domain: 'example$card.com',
                  title: 'Title $s',
                  state: SearchURLState.success,
                ),
            ],
            sources: [
              for (var s = 0; s < 8; s++)
                SearchSource(
                  url: 'https://example$card.com/page$s',
                  domain: 'example$card.com',
                  title: 'Title $s',
                  content: filler(2000),
                ),
            ],
          ),
      ];

      final encoded = encodeSearchSegments(segments);

      // Comfortably bounded, and a large improvement over persisting the
      // same text twice (extractedContent + sources[].content) uncapped,
      // which measured ~954KB for this shape before the fix.
      expect(encoded.length, lessThan(600000));
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
